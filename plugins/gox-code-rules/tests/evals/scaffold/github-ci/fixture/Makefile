.PHONY: help test lint check ensure-lint

GOLANGCI_VERSION := $(shell cat .golangci-lint-version)
GOLANGCI := ./bin/golangci-lint

help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-13s - %s\n", $$1, $$2}'

ensure-lint:
	@if [ ! -x "$(GOLANGCI)" ] || ! "$(GOLANGCI)" version 2>/dev/null | grep -q "$(GOLANGCI_VERSION:v%=%)"; then \
		curl -sSfL https://golangci-lint.run/install.sh | sh -s -- -b ./bin "$(GOLANGCI_VERSION)"; \
	fi

test: ## Run tests
	@go test -v -race -count=1 -timeout 120s ./...

lint: ensure-lint ## Run linter (pinned version)
	@$(GOLANGCI) run ./...

check: lint test ## Full local check (run before commit)
	@echo "All checks passed!"
