# PlugFest 2025 Traffic Dashboard - Makefile
# Registry and Version Configuration
REGISTRY := registry.k-paas.org/plugfest
VERSION := v1.0.3

# Service List
SERVICES := traffic-simulator data-collector data-processor data-api-service api-gateway frontend openapi-collector openapi-proxy-api

# Image names
IMAGES := $(foreach service,$(SERVICES),$(REGISTRY)/$(service):$(VERSION))

# Karmada context (adjust if needed)
KARMADA_CONTEXT := karmada-apiserver

.PHONY: help
help: ## Show this help message
	@echo "PlugFest 2025 Traffic Dashboard - Make targets"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: login
login: ## Login to K-PaaS registry (not needed for public registry)
	@echo "Using public registry $(REGISTRY) - no login required"

.PHONY: buildx-setup
buildx-setup: ## Setup Docker Buildx for multi-architecture builds
	@echo "Setting up Docker Buildx..."
	@docker buildx create --use --name multiarch-builder 2>/dev/null || docker buildx use multiarch-builder
	@echo "Buildx ready for multi-architecture builds"

.PHONY: build
build: buildx-setup ## Build all Docker images for linux/amd64
	@echo "Building all services for linux/amd64..."
	@for service in $(SERVICES); do \
		echo "Building $$service..."; \
		docker buildx build --platform linux/amd64 -t $(REGISTRY)/$$service:$(VERSION) --load ./$$service || exit 1; \
		docker tag $(REGISTRY)/$$service:$(VERSION) $(REGISTRY)/$$service:latest; \
	done
	@echo "All images built successfully!"

.PHONY: build-%
build-%: ## Build a specific service for linux/amd64 (e.g., make build-data-collector)
	@echo "Building $* for linux/amd64..."
	docker buildx build --platform linux/amd64 -t $(REGISTRY)/$*:$(VERSION) --load ./$*
	docker tag $(REGISTRY)/$*:$(VERSION) $(REGISTRY)/$*:latest

.PHONY: push
push: ## Push all Docker images to registry
	@echo "Pushing all images to $(REGISTRY)..."
	@for service in $(SERVICES); do \
		echo "Pushing $$service..."; \
		docker push $(REGISTRY)/$$service:$(VERSION) || exit 1; \
		docker push $(REGISTRY)/$$service:latest || exit 1; \
	done
	@echo "All images pushed successfully!"

.PHONY: push-%
push-%: ## Push a specific service (e.g., make push-data-collector)
	@echo "Pushing $*..."
	docker push $(REGISTRY)/$*:$(VERSION)
	docker push $(REGISTRY)/$*:latest

.PHONY: build-push
build-push: build push ## Build and push all images

.PHONY: build-push-%
build-push-%: build-% push-% ## Build and push a specific service

.PHONY: manifests
manifests: ## Generate Kubernetes manifests
	@echo "Generating Kubernetes manifests..."
	@mkdir -p k8s
	@echo "Manifests will be created in k8s/ directory"

.PHONY: deploy-karmada
deploy-karmada: ## Deploy to Karmada (all resources + policies)
	@echo "Deploying to Karmada control plane..."
	kubectl apply -f k8s/ --context=$(KARMADA_CONTEXT)
	@echo "Deployment completed!"

.PHONY: deploy-resources
deploy-resources: ## Deploy only Kubernetes resources (no policies)
	@echo "Deploying resources to Karmada..."
	kubectl apply -f k8s/namespace.yaml --context=$(KARMADA_CONTEXT) || true
	kubectl apply -f k8s/configmap.yaml --context=$(KARMADA_CONTEXT) || true
	kubectl apply -f k8s/secret.yaml --context=$(KARMADA_CONTEXT) || true
	kubectl apply -f k8s/mariadb.yaml --context=$(KARMADA_CONTEXT) || true
	kubectl apply -f k8s/redis.yaml --context=$(KARMADA_CONTEXT) || true
	kubectl apply -f k8s/traffic-simulator.yaml --context=$(KARMADA_CONTEXT) || true
	kubectl apply -f k8s/data-collector.yaml --context=$(KARMADA_CONTEXT) || true
	kubectl apply -f k8s/data-processor.yaml --context=$(KARMADA_CONTEXT) || true
	kubectl apply -f k8s/data-api-service.yaml --context=$(KARMADA_CONTEXT) || true
	kubectl apply -f k8s/api-gateway.yaml --context=$(KARMADA_CONTEXT) || true
	kubectl apply -f k8s/frontend.yaml --context=$(KARMADA_CONTEXT) || true

.PHONY: deploy-policies
deploy-policies: ## Deploy only Karmada propagation policies
	@echo "Deploying Karmada policies..."
	kubectl apply -f k8s/propagation-policy.yaml --context=$(KARMADA_CONTEXT)

.PHONY: status
status: ## Check deployment status in Karmada
	@echo "Checking Karmada deployment status..."
	kubectl get deployments -n default --context=$(KARMADA_CONTEXT)
	kubectl get services -n default --context=$(KARMADA_CONTEXT)
	kubectl get propagationpolicies -n default --context=$(KARMADA_CONTEXT)

.PHONY: clean
clean: ## Delete all resources from Karmada
	@echo "Deleting all resources from Karmada..."
	kubectl delete -f k8s/ --context=$(KARMADA_CONTEXT) --ignore-not-found=true

.PHONY: logs-%
logs-%: ## Show logs for a specific service (e.g., make logs-data-collector)
	kubectl logs -n default -l app=$* --context=$(KARMADA_CONTEXT) --tail=100

.PHONY: describe-%
describe-%: ## Describe a specific deployment (e.g., make describe-data-collector)
	kubectl describe deployment $* -n default --context=$(KARMADA_CONTEXT)

.PHONY: all
all: login build-push deploy-karmada ## Complete workflow: login, build, push, and deploy

.PHONY: images
images: ## List all built images
	@echo "Built images:"
	@for service in $(SERVICES); do \
		docker images $(REGISTRY)/$$service; \
	done

.PHONY: test-local
test-local: ## Run local tests
	@echo "Running local tests..."
	./run-local.sh stop
	./run-local.sh all

.DEFAULT_GOAL := help
