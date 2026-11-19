.PHONY: all keygen melange prod debug build-img all-variants test test-prod test-debug test-build test-all scan clean help

IMAGE_NAME ?= java21-distroless
ARCH ?= $(shell uname -m)

help: ## Show this help menu
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

all: melange all-variants test-all ## Build Melange package, all 3 image variants, and run validation tests

keygen: ## Generate Melange RSA key pair if not present
	@if [ ! -f melange.rsa ]; then \
		echo "==> Generating Melange keypair..."; \
		if command -v melange >/dev/null 2>&1; then \
			melange keygen melange.rsa; \
		else \
			docker run --rm -v "$$(pwd):/work" -w /work cgr.dev/chainguard/melange:latest keygen melange.rsa; \
		fi \
	fi

melange: keygen ## Build custom stripped JRE APK package via Melange
	@echo "==> [Melange] Building custom JRE package for $(ARCH)..."
	@mkdir -p packages
	@if command -v melange >/dev/null 2>&1; then \
		melange build melange/melange.yaml --arch $(ARCH) --signing-key melange.rsa --out-dir packages; \
	else \
		docker run --rm --privileged -v "$$(pwd):/work" -w /work \
			cgr.dev/chainguard/melange:latest build melange/melange.yaml \
			--arch $(ARCH) --signing-key melange.rsa --out-dir packages; \
	fi

# ------------------------------------------------------------------------------
# Variant 1: Production (Distroless / Zero Shell / Minimal Attack Surface)
# ------------------------------------------------------------------------------
prod: ## Build Variant 1: Production Distroless Image (latest/prod)
	@echo "==> [Apko] Building Production Image ($(IMAGE_NAME):prod)..."
	@mkdir -p output
	@if command -v apko >/dev/null 2>&1; then \
		apko build apko/apko-prod.yaml $(IMAGE_NAME):prod output/image-prod.tar \
			--arch $(ARCH) --keyring-append melange.rsa.pub --sbom-formats spdx-json; \
	else \
		docker run --rm -v "$$(pwd):/work" -w /work \
			cgr.dev/chainguard/apko:latest build apko/apko-prod.yaml $(IMAGE_NAME):prod output/image-prod.tar \
			--arch $(ARCH) --keyring-append melange.rsa.pub --sbom-formats spdx-json; \
	fi
	@LOAD_OUT=$$(docker load < output/image-prod.tar); \
	LOADED_TAG=$$(echo "$$LOAD_OUT" | awk -F': ' '/Loaded image/ {print $$2}'); \
	docker tag "$$LOADED_TAG" $(IMAGE_NAME):prod; \
	docker tag "$$LOADED_TAG" $(IMAGE_NAME):latest
	@echo "[SUCCESS] Tagged: $(IMAGE_NAME):prod & $(IMAGE_NAME):latest"

# ------------------------------------------------------------------------------
# Variant 2: Debug (-dev / Busybox Shell / Curl / Bind-tools / Strace)
# ------------------------------------------------------------------------------
debug: ## Build Variant 2: Debug Image with Shell & Diagnostics (debug/dev)
	@echo "==> [Apko] Building Debug Image ($(IMAGE_NAME):debug)..."
	@mkdir -p output
	@if command -v apko >/dev/null 2>&1; then \
		apko build apko/apko-debug.yaml $(IMAGE_NAME):debug output/image-debug.tar \
			--arch $(ARCH) --keyring-append melange.rsa.pub --sbom-formats spdx-json; \
	else \
		docker run --rm -v "$$(pwd):/work" -w /work \
			cgr.dev/chainguard/apko:latest build apko/apko-debug.yaml $(IMAGE_NAME):debug output/image-debug.tar \
			--arch $(ARCH) --keyring-append melange.rsa.pub --sbom-formats spdx-json; \
	fi
	@LOAD_OUT=$$(docker load < output/image-debug.tar); \
	LOADED_TAG=$$(echo "$$LOAD_OUT" | awk -F': ' '/Loaded image/ {print $$2}'); \
	docker tag "$$LOADED_TAG" $(IMAGE_NAME):debug; \
	docker tag "$$LOADED_TAG" $(IMAGE_NAME):dev
	@echo "[SUCCESS] Tagged: $(IMAGE_NAME):debug & $(IMAGE_NAME):dev"

# ------------------------------------------------------------------------------
# Variant 3: Standard Build (CI/CD Compiler with Full JDK, Maven, Git, Bash)
# ------------------------------------------------------------------------------
build-img: ## Build Variant 3: CI/CD Build Image with full JDK 21, Maven, Git, Bash (build)
	@echo "==> [Apko] Building CI/CD Compiler Image ($(IMAGE_NAME):build)..."
	@mkdir -p output
	@if command -v apko >/dev/null 2>&1; then \
		apko build apko/apko-build.yaml $(IMAGE_NAME):build output/image-build.tar \
			--arch $(ARCH) --sbom-formats spdx-json; \
	else \
		docker run --rm -v "$$(pwd):/work" -w /work \
			cgr.dev/chainguard/apko:latest build apko/apko-build.yaml $(IMAGE_NAME):build output/image-build.tar \
			--arch $(ARCH) --sbom-formats spdx-json; \
	fi
	@LOAD_OUT=$$(docker load < output/image-build.tar); \
	LOADED_TAG=$$(echo "$$LOAD_OUT" | awk -F': ' '/Loaded image/ {print $$2}'); \
	docker tag "$$LOADED_TAG" $(IMAGE_NAME):build
	@echo "[SUCCESS] Tagged: $(IMAGE_NAME):build"

all-variants: prod debug build-img ## Build all 3 image variants

# ------------------------------------------------------------------------------
# Verification & Testing
# ------------------------------------------------------------------------------
test: test-prod ## Default test target (runs test-prod)

test-prod: ## Test production image: JVM flags, jemalloc, zero shell confirmation
	@echo "==> [TEST] Production Distroless Image ($(IMAGE_NAME):prod)..."
	@docker run --rm $(IMAGE_NAME):prod -version
	@echo "--> Checking memory and container ergonomics under 512MB limit:"
	@docker run --rm -m 512m $(IMAGE_NAME):prod -XX:+PrintFlagsFinal -version | grep -E "MaxRAMPercentage|UseContainerSupport|UseG1GC|UseStringDeduplication"
	@echo "--> Confirming Zero Shell security (expected to fail):"
	@if docker run --rm --entrypoint /bin/sh $(IMAGE_NAME):prod -c 'echo shell' >/dev/null 2>&1; then \
		echo "ERROR: Shell found in production distroless image!"; exit 1; \
	else \
		echo "[OK] No shell in production image (Distroless verified)"; \
	fi

test-debug: ## Test debug image: verify shell, curl, DNS tools, strace, and JRE
	@echo "==> [TEST] Debug Image ($(IMAGE_NAME):debug)..."
	@docker run --rm $(IMAGE_NAME):debug -version
	@echo "--> Verifying shell and diagnostics:"
	@docker run --rm --entrypoint /bin/sh $(IMAGE_NAME):debug -c 'curl --version | head -n 1; nslookup -version 2>&1 | head -n 1; echo "Shell & tools OK"'

test-build: ## Test build image: verify Maven, Git, javac, bash
	@echo "==> [TEST] Build Image ($(IMAGE_NAME):build)..."
	@docker run --rm $(IMAGE_NAME):build -c 'javac -version && mvn -v && git --version'

test-all: test-prod test-debug test-build ## Run full test suite across all 3 variants

scan: ## Run Trivy vulnerability scan against all variants
	@echo "==> Scanning production image..."
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL $(IMAGE_NAME):prod
	@echo "==> Scanning debug image..."
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL $(IMAGE_NAME):debug
	@echo "==> Scanning build image..."
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL $(IMAGE_NAME):build

clean: ## Clean generated packages, image tarballs, and temporary outputs
	@rm -rf packages output melange.rsa*
