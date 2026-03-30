#!/usr/bin/env bash

# This script has been adapted from the dbt-core/dbt-utils repo:
#
# - https://github.com/dbt-labs/dbt-utils/blob/main/run_test.sh

BLUE='\033[1;34m'
END='\033[0m'

TARGET=${1:-snowflake-ci}

echo -e "\n${BLUE}dbt executable location${END}"
echo $(which dbt)

echo -e "\n${BLUE}dbt version info${END}"
dbt --version

# Set the profile
cd integration_tests
export DBT_PROFILES_DIR=.

echo -e "\n${BLUE}dbt debug (${TARGET})${END}"
dbt debug --target "$TARGET"

echo -e "\n${BLUE}dbt deps${END}"
dbt deps --target "$TARGET" || exit 1

# build will seed, run, and test
echo -e "\n${BLUE}dbt build (full refresh)${END}"
dbt build --target "$TARGET" --full-refresh || exit 1

# build again for incremental models
echo -e "\n${BLUE}dbt build (incremental)${END}"
dbt build --target "$TARGET" || exit 1
