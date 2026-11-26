.PHONY: help build run clean test lint lint-fix fmt check install-tools ensure-lint

APP     := demo-svc
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
COMMIT  ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
DATE    ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
LDFLAGS := -X main.version=$(VERSION) -X main.commit=$(COMMIT) -X main.date=$(DATE)

GOLANGCI_VERSION := $(shell cat .golangci-lint-version)
GOLANGCI := ./bin/golangci-lint

help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-13s - %s\n", $$1, $$2}'

build: clean ## Compile
	@go build -ldflags "$(LDFLAGS)" -o bin/$(APP) ./cmd/$(APP)

run: build ## Run
	@./bin/$(APP) --help

clean: ## Clean build output
	@rm -rf bin/

ensure-lint:
	@if [ ! -x "$(GOLANGCI)" ] || ! "$(GOLANGCI)" version 2>/dev/null | grep -q "$(GOLANGCI_VERSION:v%=%)"; then \
		curl -sSfL https://golangci-lint.run/install.sh | sh -s -- -b ./bin "$(GOLANGCI_VERSION)"; \
	fi

install-tools: ensure-lint ## Install pinned golangci-lint to ./bin
	@echo "golangci-lint $(GOLANGCI_VERSION) ready at $(GOLANGCI)"

test: ## Run tests
	@go test -v -race -count=1 -timeout 120s ./...

lint: ensure-lint ## Run linter (pinned version)
	@$(GOLANGCI) run ./...

lint-fix: ensure-lint ## Run linter with auto-fix
	@$(GOLANGCI) run --fix ./...

fmt: lint-fix ## Format code (lint + fix)
	@echo "Code formatted!"

check: fmt lint test ## Full local check (run before commit)
	@echo "All checks passed!"
