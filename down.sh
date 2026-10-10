#!/usr/bin/env bash
# Stop LocalStack. All local AWS data is discarded.
set -euo pipefail
docker stop localstack
