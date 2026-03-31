.PHONY: help setup docs lint integration_tests
.DEFAULT_GOAL := help

# Makes all arguments after the `lint` command do-nothing targets
ifeq (lint,$(firstword $(MAKECMDGOALS)))
  RUN_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(eval $(RUN_ARGS):;@:)
endif

# Initialisation recipes
setup: ## Install uv
	@if ! command -v uv; then \
		echo "Installing uv..."; \
		curl -LsSf https://astral.sh/uv/install.sh | sh; \
	fi
	uv sync

# dbt Development recipes
dbt: ## Start a dbt shell
	export DBT_PROFILES_DIR=~/.dbt/ && export SHELL=/bin/zsh && . .venv/bin/activate && exec bash

bigquery-login: ## Login to GCP with gcloud and set the project
	gcloud config set project $(GCP_PROJECT_ID)
	gcloud auth login --enable-gdrive-access --update-adc

integration_tests: ## Run integration tests
	uv run ./run_test.sh snowflake-ci
	uv run ./run_test.sh bigquery-ci

docs: ## Compile the dbt project & start dbt docs
	uv run dbt docs generate --profiles-dir ~/.dbt/
	uv run dbt docs serve

lint: ## SQLFluff lint the dbt project (run `make lint <path>` to lint specific paths)
	uv run sqlfluff lint --config ../.sqlfluff $(RUN_ARGS)


lint-fix: ## SQLFluff lint the dbt project (run `make lint <path>` to lint specific paths)
	uv run sqlfluff fix --config ../.sqlfluff $(RUN_ARGS)

clean: ## Uninstall the virtual environment
	@echo Uninstalling the virtual environment.
	rm -rf .venv/

help:	## Show targets and comments (must have ##)
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'
