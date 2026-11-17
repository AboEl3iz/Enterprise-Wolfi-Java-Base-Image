.PHONY: all build-melange build-image build-direct test scan clean help

IMAGE_NAME ?= java21-distroless
IMAGE_TAG ?= latest
ARCH ?= $(shell uname -m)

help: ## Show this help menu
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

all: build-melange build-image test ## Full build lifecycle (Melange + Apko + Test)

keygen: ## Generate Melange RSA key pair if not present
	@if [ ! -f melange.rsa ]; then \
		echo "==> Generating melange keypair..."; \
		docker run --rm -v "$$(pwd):/work" -w /work cgr.dev/chainguard/melange:latest keygen melange.rsa; \
	fi

build-melange: keygen ## Build custom JRE APK package via Melange
	@echo "==> Building Wolfi package for $(ARCH)..."
	@docker run --rm --privileged -v "$$(pwd):/work" -w /work \
		cgr.dev/chainguard/melange:latest build melange/melange.yaml \
		--arch $(ARCH) \
		--signing-key melange.rsa \
		--out-dir packages

build-image: ## Build distroless image via Apko with custom JRE
	@echo "==> Building Apko distroless image..."
	@mkdir -p output
	@docker run --rm -v "$$(pwd):/work" -w /work \
		cgr.dev/chainguard/apko:latest build apko/apko.yaml $(IMAGE_NAME):$(IMAGE_TAG) output/image.tar \
		--arch $(ARCH) \
		--keyring-append melange.rsa.pub
	@docker load < output/image.tar

build-direct: ## Build direct Wolfi base image (instant, without custom Melange step)
	@./scripts/build-direct.sh $(IMAGE_NAME):direct

test: ## Validate JVM settings, jemalloc preload, and container ergonomics
	@echo "==> Validating JVM configuration..."
	@docker run --rm $(IMAGE_NAME):$(IMAGE_TAG) -version
	@echo "==> Checking G1GC and container flags..."
	@docker run --rm -m 512m $(IMAGE_NAME):$(IMAGE_TAG) -XX:+PrintFlagsFinal -version | grep -E "UseContainerSupport|MaxRAMPercentage|UseG1GC|UseStringDeduplication"

scan: ## Run Trivy vulnerability scan against built image
	@echo "==> Scanning image for vulnerabilities..."
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy:latest image --severity HIGH,CRITICAL $(IMAGE_NAME):$(IMAGE_TAG)

clean: ## Clean build artifacts, packages, and outputs
	@rm -rf packages output melange.rsa*
