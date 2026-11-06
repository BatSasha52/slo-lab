# Thin wrappers around scripts/. On Windows without make, run the scripts
# directly from Git Bash or WSL, e.g. `bash scripts/up.sh` (see README).

SHELL := bash
.DEFAULT_GOAL := help

RATE ?= 0.5
MS ?= 400
RPS ?= 10

.PHONY: help up down cluster monitoring app rules smoke ports load fault-errors \
        fault-latency fault-clear fault-show drill test check

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

up: ## Create the cluster and deploy everything, then run the smoke test
	bash scripts/up.sh

down: ## Delete the cluster
	bash scripts/down.sh

cluster: ## Create the kind cluster only
	bash scripts/cluster-up.sh

monitoring: ## Install/upgrade the monitoring stack, rules and dashboards
	bash scripts/deploy-monitoring.sh

app: ## Build and deploy the demo app, load generator and alert receiver
	bash scripts/deploy-app.sh

thanos: ## Optional: add Thanos sidecar, store gateway, query and object storage
	bash scripts/deploy-thanos.sh

rules: ## Re-apply only the Prometheus rules
	bash scripts/render-rules.sh | kubectl apply -f -

smoke: ## Check that the running lab works end to end
	bash scripts/smoke-test.sh

ports: ## Port-forward Prometheus, Alertmanager and Grafana
	bash scripts/port-forward.sh

load: ## Set the load generator rate (RPS=10)
	bash scripts/load.sh $(RPS)

fault-errors: ## Make RATE (0.5) of /work requests fail
	bash scripts/fault.sh errors $(RATE)

fault-latency: ## Add MS (400) milliseconds to every /work request
	bash scripts/fault.sh latency $(MS)

fault-clear: ## Remove injected faults
	bash scripts/fault.sh clear

fault-show: ## Show the fault setting of each pod
	bash scripts/fault.sh show

drill: ## Run the scripted incident drill (takes over an hour)
	bash scripts/drill.sh

test: ## Run the app unit tests
	cd app && python -m pytest -q

check: ## Run the CI checks that do not need a cluster
	bash scripts/check.sh
