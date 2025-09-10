.PHONY: dbt docs lint integration_tests
.DEFAULT_GOAL := help

# Makes all arguments after the `lint` command do-nothing targets
ifeq (lint,$(firstword $(MAKECMDGOALS)))
  RUN_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(eval $(RUN_ARGS):;@:)
endif

# Initialisation recipes
poetry: ## Install poetry
	@if ! command -v poetry; then\
		curl -sSL https://install.python-poetry.org | python3 -;\
	fi
	poetry install --directory ../

# dbt Development recipes
dbt: poetry ## Start a dbt shell
	export DBT_PROFILES_DIR=~/.dbt/ && export SHELL=/bin/zsh && poetry shell

integration_tests: ## Run integration tests
	./run_test.sh

docs: poetry ## Compile the dbt project & start dbt docs
	poetry run dbt docs generate --profiles-dir ~/.dbt/
	poetry run dbt docs serve

lint: poetry ## SQLFluff lint the dbt project (run `make lint <path>` to lint specific paths)
	poetry run sqlfluff lint --config ../.sqlfluff $(RUN_ARGS)


lint-fix: poetry ## SQLFluff lint the dbt project (run `make lint <path>` to lint specific paths)
	poetry run sqlfluff fix --config ../.sqlfluff $(RUN_ARGS)

clean: ## Uninstall the dbt virtual environment
	@echo Uninstalling the Poetry virtual environment.
	poetry env remove python || rm -rf ../.venv

help:	## Show targets and comments (must have ##)
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'
