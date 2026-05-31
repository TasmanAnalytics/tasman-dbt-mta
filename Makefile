.DEFAULT_GOAL := help

.PHONY: help
help: ## Show targets and comments (must have ##)
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

.PHONY: setup
setup: ## Install project dependencies
	@if ! command -v uv; then \
		echo "Installing uv..."; \
		curl -LsSf https://astral.sh/uv/install.sh | sh; \
	fi
	uv sync
	uv run pre-commit install --install-hooks

.PHONY: bigquery-login
bigquery-login: ## Login to GCP with gcloud and set the project
	gcloud config set project $(GCP_PROJECT_ID)
	gcloud auth login --enable-gdrive-access --update-adc

.PHONY: lint
lint: ## Run linters and formatters
	@echo "\\033[0;34mpre-commit checks\\033[0m"
	SKIP=identity uv run pre-commit run --all-files --hook-stage pre-commit
	@echo "\\033[0;34mpre-push checks\\033[0m"
	SKIP=identity uv run pre-commit run --all-files --hook-stage pre-push
	@echo "\\033[0;34msqlfluff lint\\033[0m"
	pushd integration_tests && uv run sqlfluff lint; popd
	@echo "\\033[0;34msqlfluff fix\\033[0m"
	pushd integration_tests && uv run sqlfluff fix; popd

.PHONY: integration_tests
integration_tests: ## Run integration tests
	uv run ./run_test.sh snowflake-ci
	uv run ./run_test.sh bigquery-ci
