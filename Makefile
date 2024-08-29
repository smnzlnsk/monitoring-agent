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
BUILD_DIR=./bin
CONFIG_DIR=./config
BUILDER_CONFIG_DIR=$(CONFIG_DIR)/opentelemetry-collector-builder
SCRIPTS_DIR=./scripts

# Detect OS and arch
OS := $(shell uname -s)
ARCH := $(shell uname -m)

ifeq ($(OS), Darwin)
	ifeq ($(ARCH), arm64)
		OSARCH=darwin-arm64
	endif
endif

ifeq ($(OS), Linux)
	ifeq ($(ARCH), aarch64)
		OSARCH=linux-aarch64
	endif
endif
# default
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

# Variables
BINARY_NAME ?= oakestra-monitoring-agent

# Docker
DOCKER=docker
CONTAINER_NAME=monitoring-agent

# Commands
all: help

help:
	@echo "Available commands:"
	@echo "build-go \t\t build go project in $(SRC_DIR)"
	@echo "build-collector \t build opentelemetry collector"
	@echo "test \t\t\t run tests"
	@echo "fmt \t\t\t run gofmt"
	@echo "vet \t\t\t run go vet"
	@echo "mod-tidy \t\t run go mod tidy"
	@echo "install \t\t install the binary in $(SRC_DIR)"
	@echo "run-go \t\t\t run the binary in $(SRC_DIR)"
	@echo "run-collector \t\t run the collector in $(COLLECTOR_BUILD_DIR)/$(COLLECTOR_BIN)"

build-docker:
	@echo "Building docker container..."
  $(DOCKER) build --progress=plain -t $(CONTAINER_NAME):latest .


build-collector: setup
	@echo "Building collector..."
	$(OCB) --config=$(BUILDER_CONFIG_DIR)/manifest.yaml --name=$(COLLECTOR_BIN) --output-path=$(COLLECTOR_BUILD_DIR) --skip-strict-versioning

clean: 
	@echo "Cleaning..."
	$(GOCLEAN)
	rm -f $(BUILD_DIR)/$(BINARY_NAME)

setup:
	@echo "Creating necessary dirs..."
	mkdir -p $(BUILD_DIR)

test: 
	@echo "Running tests..."
	$(GOTEST) -v $(PKG)

fmt: 
	@echo "Formatting code..."
	$(GOFMT) $(PKG)

vet: 
	@echo "Vetting code..."
	$(GOVET) $(PKG)

mod-tidy: 
	@echo "Tidying up modules..."
	$(GOMOD) tidy

run-collector: build-collector
	@echo "Running collector..."
	$(COLLECTOR_BUILD_DIR)/$(COLLECTOR_BIN) --config=$(COLLECTOR_CONFIG_DIR)/opentelemetry-config.yaml

# Phony targets
.PHONY: all build-docker build-collector clean test fmt vet mod-tidy run-collector help

