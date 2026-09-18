# Operations Runbook

## Incident: Gossip Peers Stay at 0

**Symptom:**
Validator has been running for > 5 minutes but `gossip_peers` metric reports 0.

**Diagnosis:**
1. Confirm pod is running and not restarting:
   ```bash
   kubectl get pod -n solana -o wide
   kubectl describe pod -n solana <pod-name>
   ```

2. Check if UDP 8000-8026 is bound:
   ```bash
   kubectl exec -it <pod-name> -n solana -- netstat -tuln | grep -E ':(800[0-9]|801|802[0-6])'
   ```

3. Verify NSG allows inbound UDP 8000-8026:
   ```bash
   oci network security-group list --compartment-id <COMPARTMENT_ID> --display-name solana-p2p-nsg
   oci network security-group-security-rule list --security-group-id <NSG_ID>
   ```

4. Check for iptables DROP rules:
   ```bash
   kubectl exec -it <pod-name> -n solana -- iptables -L INPUT -n -v --line-numbers
   ```
   Expected: UDP traffic on 8000-8026 should not be dropped.

5. Check agave-validator logs for bootstrap entrypoint errors:
   ```bash
   kubectl logs -n solana <pod-name> -c agave-validator | tail -100
   ```

**TODO:** Document observed output from (1)–(5) in a real incident. Include line numbers of the drop rules if found.

---

## Incident: Pod Stuck in Startup for Over an Hour

**Symptom:**
Pod has been in `Running` state but not reporting metrics; agave-validator is downloading ledger snapshots and the download appears stalled.

**Diagnosis:**
1. Check snapshot download progress:
   ```bash
   kubectl exec -it <pod-name> -n solana -- du -sh /data/agave/
   ```

2. Tail agave-validator logs for snapshot errors:
   ```bash
   kubectl logs -n solana <pod-name> -c agave-validator -f --tail=50
   ```
   Look for `DownloadError`, `timeout`, or `ConnectionRefused`.

3. Confirm network egress to Solana snapshot servers:
   ```bash
   kubectl exec -it <pod-name> -n solana -- curl -I https://api.testnet.solana.com/
   ```

4. Check if PVC is full or nearly full:
   ```bash
   kubectl exec -it <pod-name> -n solana -- df -h /data/
   ```

**TODO:** Document real snapshot server endpoints, download size at failure point, and network latency from OKE to snapshot CDN.

---

## Incident: Ledger PVC Filling

**Symptom:**
Pod is evicted or logs show `No space left on device` when writing ledger entries.

**Diagnosis:**
1. Check PVC usage:
   ```bash
   kubectl get pvc -n solana
   kubectl exec -it <pod-name> -n solana -- df -h /data/
   ```

2. Break down disk usage by ledger directory:
   ```bash
   kubectl exec -it <pod-name> -n solana -- du -sh /data/agave/* | sort -h
   ```

3. Check if rocksdb compaction is running:
   ```bash
   kubectl logs -n solana <pod-name> -c agave-validator | grep -i compact
   ```

4. Determine PVC resize ability:
   ```bash
   kubectl describe pvc -n solana <pvc-name>
   kubectl get sc
   ```

**TODO:** Document actual ledger directory sizes at time of filling, PVC capacity, and time-to-fill rate.

---

## Incident: All Grafana Panels Show "No Data"

**Symptom:**
Grafana dashboards report no data for all metrics despite pods running.

**Diagnosis:**
1. Confirm Prometheus is scraping:
   ```bash
   kubectl get pod -n monitoring
   kubectl logs -n monitoring <prometheus-pod> | grep -i 'scrape\|error'
   ```

2. Check ServiceMonitor is created and valid:
   ```bash
   kubectl get servicemonitor -n solana
   kubectl describe servicemonitor -n solana <monitor-name>
   ```

3. Confirm exporter is responding on port 8080:
   ```bash
   kubectl exec -it <pod-name> -n solana -- curl -s http://127.0.0.1:8080/metrics | head -20
   ```

4. Test Prometheus target manually:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
   # Browse http://localhost:9090 > Targets > check scrape status
   ```

**TODO:** Document observed Prometheus scrape config and actual metric names returned by exporter.

---

## Incident: Node Pool Will Not Scale Up ("Out of Host Capacity")

**Symptom:**
Terraform `apply` succeeds but new worker node VM does not launch; OKE cluster shows pending node.

**Diagnosis:**
1. Check OKE node pool status:
   ```bash
   oci ce node-pool list --cluster-id <CLUSTER_ID>
   oci ce node-pool-options get --cluster-id <CLUSTER_ID> --node-pool-id <POOL_ID>
   ```

2. Check OCI compute shape availability in the subnet's AD:
   ```bash
   oci compute shape list --compartment-id <COMPARTMENT_ID> --availability-domain <AD> | jq '.data[] | select(.shape | contains("VM.Standard")) | {shape, available_cores: .ocpu_options}'
   ```

3. Check for resource quotas in compartment:
   ```bash
   oci limits quota list --compartment-id <COMPARTMENT_ID>
   oci limits resource-availability list --service-name compute --compartment-id <COMPARTMENT_ID>
   ```

4. View Kubernetes events:
   ```bash
   kubectl describe node
   kubectl get events -A | grep -i 'capacity\|insufficient'
   ```

**TODO:** Document the specific shape and AD where capacity was exhausted, and the quota limit found.

---

## Incident: Terraform Destroy Hangs

**Symptom:**
`terraform destroy` starts but appears to hang indefinitely, no progress for > 5 minutes.

**Diagnosis:**
1. Check which resources are being destroyed:
   ```bash
   terraform show
   terraform state list | head -20
   ```

2. Monitor OCI API calls in another window:
   ```bash
   oci audit event list --compartment-id <COMPARTMENT_ID> --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" | jq '.data[] | {time: .event_time, resource: .resource_name, status: .response_payload.status}'
   ```

3. Check if PVC is still being used by a terminating pod:
   ```bash
   kubectl get pvc -n solana
   kubectl get pod -n solana -o wide
   ```

4. If OCI VCN/subnet is locked in resource deletion, list dependents:
   ```bash
   oci network vcn get --vcn-id <VCN_ID>
   oci network subnet list --vcn-id <VCN_ID> --compartment-id <COMPARTMENT_ID>
   ```

**Fix:**
If PVC is blocking Terraform, manually delete the PVC and retry `terraform destroy`:
```bash
kubectl delete pvc -n solana --grace-period=0 --force
terraform destroy
```

**TODO:** Document any resource lock encountered and the order in which resources were finally destroyed.

---

## General Runbook Notes

- Always check `kubectl describe` output before searching logs; it saves time.
- Use `kubectl get events -A --sort-by='.lastTimestamp'` to see recent cluster-wide errors.
- For network issues, start with `tcpdump -ni any 'udp portrange 8000-8026' -c 50 | head -10` inside the pod, not outside.


## OCI CLI hangs instead of returning

**Symptom.** Any `oci ...` command sits indefinitely with no output and no error. Ctrl-C is the
only way out. Commonly hit on `oci os ns get` or `oci limits value list`.

**Diagnosis.** The session token from `oci session authenticate` has expired — they last about an
hour. An expired token does not produce an auth error; the CLI blocks waiting on a re-auth that
never arrives.

```bash
ls -l ~/.oci/sessions/*/token     # check the mtime
timeout 10 oci iam region-subscription list --tenancy-id "$(awk -F'= *' '/^tenancy/{print $2;exit}' ~/.oci/config)"
```

If the `timeout` call returns 124, the session is dead.

**Fix.**

```bash
oci session refresh --profile DEFAULT     # usually enough
oci session authenticate                  # if refresh fails or the token is long expired
```

The repo's scripts guard against this: they probe the session up front and wrap every call in
`timeout 30`, so they fail with an instruction rather than hanging.


## "Profile already exists" and "Profile not found" for the same name

**Symptom.** `oci session authenticate` reports
`Profile EU-FRANKFURT-1 already exists in config` and then `Config written to: ...`, and afterwards
`oci session refresh --profile EU-FRANKFURT-1` says `Profile 'EU-FRANKFURT-1' not found`.

**Diagnosis.** Both are true. The conflict check upper-cases the name; the lookup does not. If the
config holds `[eu-frankfurt-1]`, the uppercase form collides on write and misses on read. The
session itself is fine — it was written to the lowercase profile.

Also: `oci session authenticate` writes whatever profile name you type, so the live session is
frequently **not** `[DEFAULT]`, and `[DEFAULT]` may hold a long-dead token.

```bash
grep '^\[' ~/.oci/config                    # exact profile names, case included
ls -l --time-style=+%F\ %T ~/.oci/sessions/*/token   # which token is actually fresh
```

**Fix.** Use the name exactly as it appears in the config. The repo's scripts avoid the problem
entirely: `scripts/lib/oci-common.sh` tries profiles newest-token-first and probes each one, so it
finds the live session whatever it is called. Override with `OCI_CLI_PROFILE=<name>` if needed.
