# TrustyAI Guardrails Operator Makefile
#
# Controller Discovery:
#   By default, this Makefile auto-discovers imported controller modules from go.mod
#   You can override this by setting the CONTROLLERS variable:
#     make fetch-crds CONTROLLERS="github.com/org/controller1 v1.0.0 github.com/org/controller2 v2.0.0"
#   This works for: list-controllers, fetch-crds, manifests

# Image URL to use all building/pushing image targets
IMG ?= trustyai-guardrails-operator:latest

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# CONTAINER_TOOL defines the container tool to be used for building images.
CONTAINER_TOOL ?= docker

# Setting SHELL to bash allows bash commands to be executed by recipes.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen

## Tool Versions
KUSTOMIZE_VERSION ?= v5.0.1
CONTROLLER_TOOLS_VERSION ?= v0.14.0

##@ Controller Discovery

# Shell function to extract imported controllers from go.mod
# Returns: "module1 version1\nmodule2 version2\n..."
# Can be overridden by setting CONTROLLERS variable
define get-imported-controllers
grep -E 'github\.com/[^/]+/[^/]*-controller' go.mod | grep -v '^replace' | awk '{print $$1, $$2}'
endef

# CONTROLLERS can be set manually or auto-discovered from go.mod
# Format: "module1 version1 module2 version2 ..."
# Example: make fetch-crds CONTROLLERS="github.com/org/controller1 v1.0.0 github.com/org/controller2 v2.0.0"
CONTROLLERS ?=

# Helper function to get controllers list (auto-discovered if CONTROLLERS not set)
define get-controllers-list
$(if $(CONTROLLERS),$(CONTROLLERS),$(shell $(get-imported-controllers)))
endef

.PHONY: all
all: build

##@ General

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: fmt vet ## Run tests.
	go test ./... -coverprofile cover.out

##@ Build

.PHONY: build
build: fmt vet ## Build manager binary.
	go build -o bin/manager ./cmd/main.go

.PHONY: run
run: fmt vet ## Run the operator from your host.
	go run ./cmd/main.go

.PHONY: docker-build
docker-build: ## Build docker image with the manager.
	$(CONTAINER_TOOL) build -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	$(CONTAINER_TOOL) push ${IMG}

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: kustomize ## Undeploy controller from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -


.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary. If wrong version is installed, it will be overwritten.
$(CONTROLLER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/controller-gen && $(LOCALBIN)/controller-gen --version | grep -q $(CONTROLLER_TOOLS_VERSION) || \
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	test -s $(LOCALBIN)/kustomize || GOBIN=$(LOCALBIN) go install sigs.k8s.io/kustomize/kustomize/v5@$(KUSTOMIZE_VERSION)

.PHONY: manifests
manifests: fetch-crds controller-gen ## Generate RBAC manifests for this operator.
	@echo "Generating RBAC manifests for trustyai-guardrails-operator..."
	@echo "Finding imported controller module paths..."
	@CONTROLLER_LIST="$(strip $(get-controllers-list))"; \
	if [ -z "$$CONTROLLER_LIST" ]; then \
		echo "Error: No controllers found. Add controllers to go.mod or set CONTROLLERS variable."; \
		exit 1; \
	fi; \
	CONTROLLER_PATHS="./cmd/..."; \
	MODULES=$$(echo "$$CONTROLLER_LIST" | awk '{for(i=1;i<=NF;i+=2){print $$i}}'); \
	for MODULE in $$MODULES; do \
		MODULE_PATH=$$(go list -m -f '{{.Dir}}' $$MODULE 2>/dev/null); \
		if [ -z "$$MODULE_PATH" ]; then \
			echo "Warning: Module $$MODULE not found. Run 'go mod download' first."; \
		else \
			echo "  Found $$MODULE at: $$MODULE_PATH"; \
			CONTROLLER_PATHS="$$CONTROLLER_PATHS;$$MODULE_PATH/controllers/..."; \
		fi; \
	done; \
	echo "Running controller-gen on local code and imported controllers..."; \
	echo "  Paths: $$CONTROLLER_PATHS"; \
	$(CONTROLLER_GEN) rbac:roleName=manager-role \
		paths="$$CONTROLLER_PATHS" \
		output:rbac:artifacts:config=config/rbac
	@echo "✓ RBAC manifests generated in config/rbac/"

.PHONY: generate
generate: ## This operator has no API types of its own (imports from controllers).
	@echo "This operator imports API types from external controllers."
	@echo "No code generation needed for this operator."
	@echo "Run 'make manifests' to generate RBAC for the operator."

.PHONY: list-controllers
list-controllers: ## List all imported guardrails controllers and their versions.
	@echo "Imported Guardrails Controllers:"
	@echo "================================"
	@CONTROLLER_LIST="$(strip $(get-controllers-list))"; \
	if [ -z "$$CONTROLLER_LIST" ]; then \
		echo "  (none found)"; \
	else \
		echo "$$CONTROLLER_LIST" | xargs -n2 | awk '{printf "  %-50s %s\n", $$1, $$2}'; \
	fi
	@echo ""
	@echo "To fetch CRDs for these controllers, run: make fetch-crds"
	@echo "To override, use: make <target> CONTROLLERS=\"module1 v1.0.0 module2 v2.0.0\""

.PHONY: fetch-crds
fetch-crds: ## Fetch CRDs and RBAC roles from all imported guardrails controllers matching go.mod versions.
	@echo "Fetching CRDs and RBAC from imported guardrails controllers..."
	@mkdir -p config/crd config/rbac
	@CONTROLLER_LIST="$(strip $(get-controllers-list))"; \
	if [ -z "$$CONTROLLER_LIST" ]; then \
		echo "No controller modules found"; \
		echo "Set CONTROLLERS variable or add controllers to go.mod"; \
		exit 0; \
	fi; \
	echo "$$CONTROLLER_LIST" | xargs -n2 | while read -r MODULE VERSION; do \
		if [ -z "$$MODULE" ] || [ -z "$$VERSION" ]; then continue; fi; \
		CONTROLLER_NAME=$$(basename $$MODULE); \
		echo ""; \
		echo "Processing $$CONTROLLER_NAME ($$VERSION)..."; \
		ORG=$$(echo $$MODULE | cut -d'/' -f2); \
		REPO=$$(echo $$MODULE | cut -d'/' -f3); \
		echo "  Repository: $$ORG/$$REPO"; \
		API_URL="https://api.github.com/repos/$$ORG/$$REPO/contents/config/crd/bases?ref=$$VERSION"; \
		echo "  Fetching CRD list via GitHub API..."; \
		CRD_LIST=$$(curl -sSL "$$API_URL" 2>/dev/null); \
		if echo "$$CRD_LIST" | grep -q '"message".*"Not Found"'; then \
			echo "  ✗ Version $$VERSION not found in repository"; \
			echo "  Ensure $$VERSION tag exists at https://github.com/$$ORG/$$REPO"; \
			continue; \
		fi; \
		if echo "$$CRD_LIST" | grep -q '"message"'; then \
			echo "  ✗ Failed to fetch CRD list from GitHub API"; \
			echo "  API Response: $$(echo "$$CRD_LIST" | grep '"message"' | head -1)"; \
			continue; \
		fi; \
		echo "$$CRD_LIST" | grep '"download_url"' | sed 's/.*"download_url": "\([^"]*\)".*/\1/' | while read -r DOWNLOAD_URL; do \
			if [ -z "$$DOWNLOAD_URL" ]; then continue; fi; \
			CRD_FILE=$$(basename $$DOWNLOAD_URL); \
			if echo "$$CRD_FILE" | grep -q '\.yaml$$'; then \
				if curl -sSLf "$$DOWNLOAD_URL" -o "config/crd/$$CRD_FILE" 2>/dev/null; then \
					echo "  ✓ Fetched CRD: $$CRD_FILE"; \
				else \
					echo "  ✗ Failed to fetch CRD: $$CRD_FILE"; \
				fi; \
			fi; \
		done; \
		echo "  Fetching RBAC editor/viewer roles..."; \
		RBAC_URL="https://api.github.com/repos/$$ORG/$$REPO/contents/config/rbac?ref=$$VERSION"; \
		RBAC_LIST=$$(curl -sSL "$$RBAC_URL" 2>/dev/null); \
		echo "$$RBAC_LIST" | grep '"download_url"' | sed 's/.*"download_url": "\([^"]*\)".*/\1/' | while read -r DOWNLOAD_URL; do \
			if [ -z "$$DOWNLOAD_URL" ]; then continue; fi; \
			RBAC_FILE=$$(basename $$DOWNLOAD_URL); \
			if echo "$$RBAC_FILE" | grep -qE '(editor|viewer)_role\.yaml$$'; then \
				if curl -sSLf "$$DOWNLOAD_URL" -o "config/rbac/$$RBAC_FILE" 2>/dev/null; then \
					echo "  ✓ Fetched RBAC: $$RBAC_FILE"; \
				else \
					echo "  ✗ Failed to fetch RBAC: $$RBAC_FILE"; \
				fi; \
			fi; \
		done; \
	done
	@echo ""
	@echo "✓ Fetch complete. CRDs in config/crd, RBAC in config/rbac"
	@echo "Commit these files to your repository for offline/standalone use"

# Generate the full set of manifests to deploy the TrustyAI Guardrails operator, with a customizable deployment namespace and operator image
OPERATOR_IMAGE ?= quay.io/trustyai/trustyai-guardrails-operator:latest
.PHONY: manifest-gen
manifest-gen: kustomize ## Generate release manifest bundle with custom namespace and image.
	@echo "Usage: make manifest-gen NAMESPACE=<namespace> OPERATOR_IMAGE=<image>"
	@echo "Example: make manifest-gen NAMESPACE=my-namespace OPERATOR_IMAGE=quay.io/myorg/trustyai-guardrails-operator:latest"
	@mkdir -p release
	@if [ -z "$(NAMESPACE)" ]; then echo "Error: NAMESPACE argument is required"; exit 1; fi
	$(KUSTOMIZE) build config/default | sed "s|namespace: trustyai-guardrails-operator-system|namespace: $(NAMESPACE)|g" | sed "s|image: controller:latest|image: $(OPERATOR_IMAGE)|g" > release/trustyai_guardrails_bundle.yaml
	@echo "✓ Release manifest generated at release/trustyai_guardrails_bundle.yaml"
	@echo "  Namespace: $(NAMESPACE)"
	@echo "  Image: $(OPERATOR_IMAGE)"