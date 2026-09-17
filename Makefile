SHELL      := /bin/bash
CHART      := charts/solana-node
ENV        := terraform/envs/oci-testnet
KIND_NAME  := solana-dev
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
