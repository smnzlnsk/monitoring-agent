# Go parameters
GOCMD=go
GOBUILD=$(GOCMD) build
GOCLEAN=$(GOCMD) clean
GOTEST=$(GOCMD) test
GOFMT=$(GOCMD) fmt
GOVET=$(GOCMD) vet
GOMOD=$(GOCMD) mod
BINARY_NAME=oakestra-monitoring-agent
PKG=./...

# Directories
SRC_DIR=./cmd/$(BINARY_NAME)
BINARY_DIR=./bin
BUILD_DIR=./build
CONFIG_DIR=./config
BUILDER_CONFIG_DIR=$(CONFIG_DIR)/opentelemetry-collector-builder
SCRIPTS_DIR=./scripts

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
endif
# default
GOOS ?= unsupported
GOARCH ?= unsupported
OSARCH ?= unknown

# OpenTelemetry Collector Builder
OCB=builder
#OCB=$(SCRIPTS_DIR)/ocb-$(OSARCH)
COLLECTOR_BIN=agent
COLLECTOR_BUILD_DIR=/tmp/oakestra-monitoring-agent
COLLECTOR_CONFIG_DIR=$(CONFIG_DIR)/opentelemetry-collector

# Versioning
VERSION=$(shell git describe --tags --always)
COMMIT=$(shell git rev-parse --short HEAD)
DATE=$(shell date +%Y-%m-%dT%H:%M:%SZ)

# Go build flags
LDFLAGS=-ldflags "-X 'main.Version=$(VERSION)' -X 'main.Commit=$(COMMIT)' -X 'main.Date=$(DATE)'"
BUILDER_LDFLAGS="-X 'main.Version=$(VERSION)' -X 'main.Commit=$(COMMIT)' -X 'main.Date=$(DATE)'"

# Variables
BINARY_NAME ?= oakestra-monitoring-agent

# Docker
DOCKER=docker
CONTAINER_NAME=monitoring-agent
MAKE=make

# Commands
all: help

help:
	@echo "Available commands:"
	@echo "build-docker \t\t build docker image"
	@echo "build \t\t\t build opentelemetry collector"
	@echo "test \t\t\t run tests"
	@echo "fmt \t\t\t run gofmt"
	@echo "vet \t\t\t run go vet"
	@echo "mod-tidy \t\t run go mod tidy"
	@echo "run \t\t\t run the collector in $(COLLECTOR_BUILD_DIR)/$(COLLECTOR_BIN)"

push: manager
	@echo "Pushing bin to github..."
	@git add bin
	@git commit -m "Pushed build $(COMMIT) on $(DATE)"
	@git push

.PHONY: build-bin
build-bin: build
	@mkdir -p $(BINARY_DIR)
	@cp -r $(COLLECTOR_BUILD_DIR)/$(COLLECTOR_BIN)* $(BINARY_DIR)/

.PHONY: build-docker
build-docker:
  docker build --progress=plain -t monitoring-manager:latest .


.PHONY: build
build: build-darwin build-linux


.PHONY: build-darwin
build-darwin:
	@echo "Building collector for darwin... "
	GOOS=darwin GOARCH=arm64 $(OCB) --ldflags=$(BUILDER_LDFLAGS) --config=$(BUILDER_CONFIG_DIR)/manifest.yaml --name=$(COLLECTOR_BIN)_darwin_arm64 --output-path=$(COLLECTOR_BUILD_DIR) --skip-strict-versioning

.PHONY: build-linux
build-linux:
	GOOS=linux GOARCH=arm64 $(OCB) --ldflags=$(BUILDER_LDFLAGS) --config=$(BUILDER_CONFIG_DIR)/manifest.yaml --name=$(COLLECTOR_BIN)_linux_arm64 --output-path=$(COLLECTOR_BUILD_DIR) --skip-strict-versioning

.PHONY: clean
clean:
	@echo "Cleaning up..."
	@rm -r $(BINARY_DIR)

.PHONY: test
test:
	@echo "Running tests..."
	$(GOTEST) -v $(PKG)

.PHONY: fmt
fmt:
	@echo "Formatting code..."
	$(GOFMT) $(PKG)

.PHONY: vet
vet:
	@echo "Vetting code..."
	$(GOVET) $(PKG)

.PHONY: mod-tidy
mod-tidy: 
	@echo "Tidying up modules..."
	$(GOMOD) tidy

.PHONY: run
run: manager
	@echo "Running collector..."
	$(BINARY_DIR)/$(COLLECTOR_BIN)_$(GOOS)_$(GOARCH) --config=$(COLLECTOR_CONFIG_DIR)/opentelemetry-config.yaml

.PHONY: manager
manager: bin
ifeq ($(wildcard $(BINARY_DIR)/$(COLLECTOR_BIN)*),)
	$(MAKE) build-bin
endif

.PHONY: bin
bin:
ifeq ($(wildcard $(BINARY_DIR)),)
	@mkdir -p $(BINARY_DIR)
endif

