#!/usr/bin/env bash
# Start LocalStack (if needed) and deploy the whole stack.
set -euo pipefail

: "${LOCALSTACK_AUTH_TOKEN:?Set LOCALSTACK_AUTH_TOKEN first}"
: "${TF_VAR_slack_webhook_url:?Set TF_VAR_slack_webhook_url first}"

export AWS_ENDPOINT_URL=http://localhost:4566

if docker ps --format '{{.Names}}' | grep -q '^localstack$'; then
  echo "LocalStack is already running"
elif docker ps -a --format '{{.Names}}' | grep -q '^localstack$'; then
  docker start localstack >/dev/null
else
  docker run -d --name localstack -p 4566:4566 \
    -e LOCALSTACK_AUTH_TOKEN="$LOCALSTACK_AUTH_TOKEN" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    localstack/localstack >/dev/null
fi

echo "Waiting for LocalStack to be ready..."
until curl -s http://localhost:4566/_localstack/health | grep -qE '"s3": "(running|available)"'; do
  sleep 2
done

# The free tier loses its data on restart, so drop stale local Terraform state.
# Never do this against a real AWS account.
if ! aws s3api head-bucket --bucket cloud-soar-test-bucket >/dev/null 2>&1; then
  rm -f terraform.tfstate terraform.tfstate.backup
fi

terraform init -input=false
terraform apply -auto-approve
