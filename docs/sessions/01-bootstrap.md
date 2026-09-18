# Session 1 — "Can this even exist?"

**Goal:** retire every hard blocker in one evening. Nothing in sessions 2–4 is interesting if the
image won't build or the cluster won't come up, so both are attempted tonight, in parallel.

**Budget:** ~4 hours, of which ~1 hour is unattended compile time you spend on step 4.

**Deadline context:** trial day 1 was ~2026-09-10, so day 30 lands ~2026-10-09 and the
capture deadline (T-4) is ~**2026-10-05**. Confirm the real date in step 1 — everything downstream
keys off it.

---

## 0. Already done — do not redo

Measured on 2026-09-18 against the live tenancy:

| Fact | Value |
|---|---|
| Credits | €0.00 spent of €250.00 |
| Home region | `eu-frankfurt-1` |
| Target AD | `fSEo:EU-FRANKFURT-1-AD-1` |
| `standard-e5-core-count` | **13** per AD (memory 208 GB) — the chosen shape |
| `standard-e3-core-ad-count` | 16 per AD (memory 277 GB) — fallback |
| `standard-e4-core-count` | **0** — E4 unavailable, do not attempt |
| `total-storage-gb` | **30720** per AD — storage is not a constraint |
| `total-free-storage-gb` | 200 — the Always Free allowance, **not** your limit |

Limit increase requests: **not required.** The only one with any value is
`standard-e5-core-count` 13 → 16 to reach the multipath threshold for Ultra High Performance
volumes, which testnet does not need. `./scripts/request-limit-increases.sh` exists if you want it.

---

## 1. Confirm the trial terms (15 min)

- [ ] Console → Billing & Cost Management → **Credits**. Record the exact **expiry date** and
      remaining balance.
- [ ] Note whether this is a standard trial or a promotional one. Some promotional trials are
      **suspended immediately** at expiry with no Always Free landing at all.
- [ ] Put **T-4 days** in your calendar as the capture deadline, not day 30.
- [ ] `mkdir -p docs/evidence/oci && ` screenshot the credits page into it.

> At day 30 you lose the ability to **create** paid resources. Existing ones survive only "a few
> days". Every `terraform apply`, node-pool resize and cluster rebuild must happen before then.

**Done when:** you have a real date, not an assumption.

---

## 2. Guardrail before the thing it guards (10 min)

- [ ] `cp terraform/envs/oci-testnet/terraform.tfvars.example terraform/envs/oci-testnet/terraform.tfvars`
- [ ] Fill in `compartment_id`, `ssh_public_key`, `admin_cidr` (`curl -s ifconfig.me`), and
      `budget_alert_email`. `region` and `availability_domain` are already correct.
- [x] **Remote state — done 2026-09-18.** `./scripts/bootstrap-state.sh` created the versioned
      bucket `tfstate-solana-validator-k8s` (namespace `frbfohzod0ut`, NoPublicAccess), minted the
      S3-compatible credential into `terraform/.s3-credentials` (0600, gitignored), and wrote
      `terraform/envs/oci-testnet/backend.hcl`.

      Before **every** terraform command in this repo:
      ```bash
      source terraform/.s3-credentials
      ```
      The credentials live in the environment on purpose — never in a file Terraform reads.
- [ ] Apply **only** the budget first:

```bash
source terraform/.s3-credentials
cd terraform/envs/oci-testnet
terraform init -backend-config=backend.hcl
terraform apply -target=module.oke.oci_budget_budget.trial \
                -target=module.oke.oci_budget_alert_rule.forecast_80
```

If `terraform init` fails with an opaque 400, the cause is almost always a missing
`skip_s3_checksum` — it is already in `backend.hcl`, so check the file was actually passed.

**Done when:** the forecast alert exists in the Console before any billable resource does.

---

## 3. Start the image build FIRST (unattended, ~45–70 min)

Start this before the Terraform work — it is the long pole and it runs without you.

- [ ] Launch a **throwaway** instance by hand in the Console (not Terraform — it is disposable and
      you want it gone tonight):
      `VM.Standard.E5.Flex`, 8 OCPU / 96 GB, Oracle Linux 9, **100 GB boot volume**.

> The 100 GB is not padding. The cargo target dir runs 30–50 GB. Do **not** try this on a
> GitHub-hosted runner (~14 GB free) — it dies partway through linking.

- [ ] Install Docker, clone the repo, and start the build detached so an SSH drop doesn't kill it:

```bash
sudo dnf install -y docker git && sudo systemctl enable --now docker
git clone https://github.com/<you>/solana-validator-k8s && cd solana-validator-k8s
nohup sudo docker build -f docker/Dockerfile -t agave:4.2.2 . > build.log 2>&1 &
tail -f build.log
```

- [ ] **Record the wall-clock build time.** It goes in the README — nobody else publishes it.
- [ ] Fill in `TARBALL_SHA256` in the Dockerfile from
      `curl -sL https://release.anza.xyz/v4.2.2/solana-release-x86_64-unknown-linux-gnu.tar.bz2 | sha256sum`
- [ ] Push to `ghcr.io/<you>/agave:4.2.2`.

**Fallback, if it fails or overruns:** `ghcr.io/dysnix/docker-agave:v4.2.2` (108 MB, Apache-2.0,
amd64). Take it without hesitation and ship your own Dockerfile anyway — the build is the artifact,
not the blocker.

**Done when:** `docker run --rm <image> agave-validator --version` prints `4.2.2`.

---

## 4. While it builds: stand up the cluster (~60–90 min)

- [ ] `terraform apply` the full module.
- [ ] Watch for these three, in the order they bite:

| Symptom | Cause | Fix |
|---|---|---|
| `Out of host capacity` | Frankfurt is busy; capacity reservations are unavailable to trial accounts | Try AD-2, then AD-3, then `-var node_shape=VM.Standard.E3.Flex -var node_ocpus=8 -var node_memory_gb=96` |
| Nodes stuck `NotReady`, generic image-pull timeout | Missing service gateway | Already in `network.tf` — verify it applied |
| `LimitExceeded` on any resource | A limit you haven't measured | `oci limits value list --service-name <svc> -c <tenancy> --all` |

- [ ] `$(terraform output -raw kubeconfig_command)`
- [ ] `kubectl get nodes -o wide` — expect one Ready worker with a **public IP**.
- [ ] Verify the node tuning landed (this is the thing that silently doesn't):

```bash
ssh opc@<node-ip> 'sysctl net.core.rmem_max; cat /proc/$(pgrep containerd)/limits | grep -E "open files|locked memory"'
ssh opc@<node-ip> 'sudo iptables -L INPUT -n -v --line-numbers' | tee docs/evidence/network/iptables-after.log
```

Expect `rmem_max = 134217728`, `Max open files 1000000`, and ACCEPT rules for 8000:8026 **above**
the REJECT line. If the ACCEPT rules are below it, cloud-init used `-A` instead of `-I` and gossip
will silently fail in Session 3.

**Done when:** one Ready worker with a public IP, and the tuning is proven on the node rather than
assumed from the cloud-init source.

---

## 5. Stop the bleeding (5 min)

- [ ] `make pause` — scale the node pool to 0.
- [ ] **Terminate the build VM.** Its 100 GB boot volume is billable and its job is done.
- [ ] `make cost` or check Cost Analysis. Compare against ~$0.50 for the build VM plus a few hours
      of worker time.

**Done when:** `oci compute instance list -c <tenancy> --lifecycle-state RUNNING` returns nothing.

---

## Definition of done for Session 1

1. A real trial expiry date, in your calendar as T-4.
2. Budget alerts live.
3. An `agave-validator 4.2.2` binary in a container you control (yours or dysnix).
4. One Ready OKE worker with a public IP, tuning verified on the node.
5. Everything scaled to zero.

If 3 and 4 both hold, nothing in sessions 2–4 can fail in a way that costs you the project. That
is the entire point of tonight.

## If you run out of time

Drop step 4 before step 3. The cluster takes 20 minutes to rebuild; a failed image build discovered
in Session 3 costs you the week.
