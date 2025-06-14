# Go parameters
GOCMD=go
BINARY_NAME=monitoringagent
PKG=./...

# Directories
BUILD_DIR=/tmp/monitoring-agent
CONFIG_DIR=./config
BUILDER_CONFIG_DIR=$(CONFIG_DIR)/opentelemetry-collector-builder
COLLECTOR_CONFIG_DIR=$(CONFIG_DIR)/opentelemetry-collector

# Detect OS and arch
OS := $(shell uname -s)
ARCH := $(shell uname -m)

ifeq ($(OS), Darwin)
	ifeq ($(ARCH), arm64)
		GOOS=darwin
		GOARCH=arm64
	endif
endif

ifeq ($(OS), Linux)
	ifeq ($(ARCH), aarch64)
		GOOS=linux
		GOARCH=arm64
	endif
	ifeq ($(ARCH), amd64)
		GOOS=linux
		GOARCH=amd64
	endif
endif
# default
GOOS ?= unsupported
GOARCH ?= unsupported
OSARCH ?= unknown

# OpenTelemetry Collector Builder
OCB=builder

# Versioning
VERSION=$(shell git describe --tags --always)
COMMIT=$(shell git rev-parse --short HEAD)
DATE=$(shell date +%Y-%m-%dT%H:%M:%SZ)

# Go build flags
LDFLAGS=-ldflags "-X 'main.Version=$(VERSION)' -X 'main.Commit=$(COMMIT)' -X 'main.Date=$(DATE)'"
BUILDER_LDFLAGS="-X 'main.Version=$(VERSION)' -X 'main.Commit=$(COMMIT)' -X 'main.Date=$(DATE)'"

# Docker
DOCKER=docker
CONTAINER_NAME=monitoring-agent
MAKE=make

# Monitoring configuration
METRICS_ENDPOINT=http://localhost:55681/metrics
METRICS_OUTPUT=~/benchmarks/agent/run_$(shell date +%Y%m%d_%H%M%S).csv
METRICS_INTERVAL=1
METRICS_FILTER=otelcol_process_

.PHONY: docker
docker:
	$(DOCKER) build --progress=plain -t $(CONTAINER_NAME):latest .

.PHONY: dev
dev:
	$(OCB) --config=$(BUILDER_CONFIG_DIR)/dev-manifest.yaml --skip-strict-versioning

.PHONY: run
run: dev
	@MACHINE_ID=$$(curl -sf http://localhost:50100/id); \
	if [ $$? -ne 0 ]; then \
		echo "Error: Failed to get machine ID from http://localhost:50100/id"; \
		exit 1; \
	fi; \
	OTEL_RESOURCE_MACHINE_ID=$${MACHINE_ID}-monitoring-agent \
	sudo -E $(BUILD_DIR)/$(BINARY_NAME) --config=$(COLLECTOR_CONFIG_DIR)/opentelemetry-config.yaml

.PHONY: run-with-monitoring
run-with-monitoring: dev
	@echo "Starting monitoring agent with metrics collection..."
	@MACHINE_ID=$$(curl -sf http://localhost:50100/id); \
	if [ $$? -ne 0 ]; then \
		echo "Error: Failed to get machine ID from http://localhost:50100/id"; \
		exit 1; \
	fi; \
	echo "Starting OpenTelemetry Collector..."; \
	OTEL_RESOURCE_MACHINE_ID=$${MACHINE_ID}-monitoring-agent \
	sudo -E $(BUILD_DIR)/$(BINARY_NAME) --config=$(COLLECTOR_CONFIG_DIR)/opentelemetry-config.yaml & \
	COLLECTOR_PID=$$!; \
	echo "Collector started with PID: $$COLLECTOR_PID"; \
	echo "Waiting for collector to be ready..."; \
	for i in $$(seq 1 30); do \
		if curl -sf $(METRICS_ENDPOINT) > /dev/null 2>&1; then \
			echo "Collector is ready!"; \
			break; \
		fi; \
		if [ $$i -eq 30 ]; then \
			echo "Error: Collector failed to start within 30 seconds"; \
			kill $$COLLECTOR_PID 2>/dev/null || true; \
			exit 1; \
		fi; \
		echo "Waiting for collector... ($$i/30)"; \
		sleep 1; \
	done; \
	echo "Starting prometheus-to-csv monitoring..."; \
	./prometheus-to-csv.sh -e $(METRICS_ENDPOINT) -o $(METRICS_OUTPUT) -i $(METRICS_INTERVAL) -v -f $(METRICS_FILTER) & \
	METRICS_PID=$$!; \
	echo "Metrics collection started with PID: $$METRICS_PID"; \
	echo "Metrics will be saved to: $(METRICS_OUTPUT)"; \
	trap 'echo "Stopping monitoring..."; kill $$METRICS_PID 2>/dev/null || true; kill $$COLLECTOR_PID 2>/dev/null || true; echo "Monitoring stopped."; exit 0' INT TERM; \
	wait $$COLLECTOR_PID

.PHONY: build-remote
build-remote:
	$(OCB) --config=$(BUILDER_CONFIG_DIR)/remote-manifest.yaml --skip-strict-versioning
