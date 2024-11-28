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

.PHONY: docker
docker:
	$(DOCKER) build --progress=plain -t $(CONTAINER_NAME):latest .

.PHONY: dev
dev:
	$(OCB) --config=$(BUILDER_CONFIG_DIR)/dev-manifest.yaml --skip-strict-versioning

.PHONY: run
run:
	sudo $(BUILD_DIR)/$(BINARY_NAME) --config=$(COLLECTOR_CONFIG_DIR)/opentelemetry-config.yaml

.PHONY: build-remote
build-remote:
	$(OCB) --config=$(BUILDER_CONFIG_DIR)/remote-manifest.yaml --skip-strict-versioning
