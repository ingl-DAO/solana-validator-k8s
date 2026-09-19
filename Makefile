SHELL      := /bin/bash
CHART      := charts/solana-node
ENV        := terraform/envs/oci-testnet
KIND_NAME  := solana-dev
KPS_VERSION := 91.4.1
RELEASE    := solana

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# --- local, no cloud ---------------------------------------------------------------------------
.PHONY: dev-up
dev-up: ## kind cluster + chart in test-validator mode. No cloud credentials needed.
	kind create cluster --config terraform/local/kind-cluster.yaml || true
	helm upgrade --install $(RELEASE) $(CHART) \
	  -f $(CHART)/values-test-validator.yaml \
	  --set persistence.storageClassName=standard \
	  --wait --timeout 10m

.PHONY: dev-down
dev-down: ## Delete the kind cluster
	kind delete cluster --name $(KIND_NAME)

# --- quality -----------------------------------------------------------------------------------
.PHONY: follower-local
follower-local: ## Real testnet node on kind, behind NAT (repair-only). Needs ~10GB free RAM.
	kind create cluster --config terraform/local/kind-cluster.yaml || true
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
	helm repo update >/dev/null
	helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
	  --version $(KPS_VERSION) --namespace monitoring --create-namespace \
	  -f deploy/monitoring/kube-prometheus-stack-values.yaml --wait --timeout 15m
	kubectl get secret $(RELEASE)-solana-node-identity >/dev/null 2>&1 || ( \
	  tmp=$$(mktemp -d); \
	  docker run --rm -v $$tmp:/out --entrypoint solana-keygen ghcr.io/marcjazz/agave:4.2.2 \
	    new --no-bip39-passphrase -s -o /out/identity.json >/dev/null; \
	  kubectl create secret generic $(RELEASE)-solana-node-identity --from-file=identity.json=$$tmp/identity.json; \
	  rm -rf $$tmp )
	helm upgrade --install $(RELEASE) $(CHART) -f $(CHART)/values-testnet-follower-local.yaml --timeout 20m
	@echo
	@echo "Deployed. It will be NOT READY for a long time - snapshot fetch, unpack, then replay."
	@echo "  kubectl logs sts/$(RELEASE)-solana-node -c validator -f"
	@echo "  kubectl exec sts/$(RELEASE)-solana-node -c validator -- solana catchup --our-localhost 8899"
	@echo
	@echo "Watch for OOMKilled - 9Gi is a guess, not a measurement:"
	@echo "  kubectl get pod -l app.kubernetes.io/name=solana-node -w"

.PHONY: lint
lint: ## terraform fmt/validate + helm lint + kubeconform
	terraform -chdir=$(ENV) fmt -check -recursive
	terraform -chdir=terraform/modules/oci-oke fmt -check -recursive
	terraform -chdir=terraform/modules/oci-oke init -backend=false -input=false >/dev/null
	terraform -chdir=terraform/modules/oci-oke validate
	helm lint $(CHART) -f $(CHART)/values-test-validator.yaml
	helm lint $(CHART) -f $(CHART)/values-testnet-follower.yaml
	$(MAKE) template | kubeconform -strict -summary -ignore-missing-schemas

.PHONY: template
template: ## Render both modes
	@helm template $(RELEASE) $(CHART) -f $(CHART)/values-test-validator.yaml
	@helm template $(RELEASE) $(CHART) -f $(CHART)/values-testnet-follower.yaml

.PHONY: policy
policy: ## Run only the custom Solana security policies
	checkov -d terraform/ --external-checks-dir policies --compact --check CKV_SOLANA_1,CKV_SOLANA_2

.PHONY: security
security: ## Full IaC scan (built-in + custom). Expect 0 failed, 9 skipped-with-reason.
	checkov -d terraform/ --external-checks-dir policies --compact

.PHONY: fmt
fmt: ## Rewrite terraform formatting in place
	terraform fmt -recursive terraform/

# --- cloud -------------------------------------------------------------------------------------
.PHONY: up
up: ## Provision OKE + apply the chart in follower mode
	./scripts/up.sh

.PHONY: down
down: ## Destroy everything and assert zero orphans
	./scripts/down.sh

.PHONY: pause
pause: ## Scale the node pool to 0. THIS is the cost model: $13.96 vs $136.12.
	terraform -chdir=$(ENV) apply -auto-approve -var node_pool_size=0

.PHONY: resume
resume: ## Scale the node pool back to 1
	terraform -chdir=$(ENV) apply -auto-approve -var node_pool_size=1

.PHONY: cost
cost: ## Pull actual spend from the OCI usage API
	./scripts/cost-check.sh

# --- evidence ----------------------------------------------------------------------------------
.PHONY: capture
capture: ## Capture everything needed to survive the trial cliff
	./scripts/capture-evidence.sh

.PHONY: dashboard
dashboard: ## Import the exporter's dashboard, rewriting its hardcoded datasource uid
	curl -fsSL -o $(CHART)/dashboards/solana-node.json \
	  https://raw.githubusercontent.com/asymmetric-research/solana-exporter/master/prometheus/solana-dashboard.json
	# The upstream JSON hardcodes datasource uid 'fe2dataaouznkf', which does not exist in
	# kube-prometheus-stack (whose uid is 'prometheus'). Without this every panel is empty.
	sed -i 's/fe2dataaouznkf/prometheus/g' $(CHART)/dashboards/solana-node.json
