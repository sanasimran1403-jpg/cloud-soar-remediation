#!/usr/bin/env bash
# End-to-end test for the S3 auto-remediation flow.
# Usage: ./test_flow.sh approve|deny|timeout
set -u
export AWS_ENDPOINT_URL=http://localhost:4566
B=cloud-soar-test-bucket
MODE=${1:-approve}

SM=$(aws stepfunctions list-state-machines \
  --query "stateMachines[?name=='cloud-soar-s3-flow'].stateMachineArn" --output text)
[ -n "$SM" ] || { echo "State machine not found. Run ./up.sh first."; exit 1; }

# Stop any executions still waiting from earlier runs
for E in $(aws stepfunctions list-executions --state-machine-arn "$SM" \
  --status-filter RUNNING --query "executions[].executionArn" --output text); do
  aws stepfunctions stop-execution --execution-arn "$E" >/dev/null
done

echo "== Making the bucket public"
aws s3api delete-public-access-block --bucket "$B"
aws s3api put-bucket-acl --bucket "$B" --acl public-read
aws events put-events --entries file://event.json >/dev/null
echo "ACL before: $(aws s3api get-bucket-acl --bucket "$B" --query 'Grants[].Grantee.URI' --output text)"

if [ "$MODE" = "timeout" ]; then
  echo ">> Do nothing in Slack. Waiting for the approval timeout."
else
  echo ">> Open Slack (#security-alerts), click '$MODE' in the newest message, then confirm."
fi

echo "== Waiting for the execution to finish (up to 200 seconds)"
EX=""
STATUS="RUNNING"
for _ in $(seq 1 40); do
  sleep 5
  EX=$(aws stepfunctions list-executions --state-machine-arn "$SM" \
    --max-results 1 --query "executions[0].executionArn" --output text)
  STATUS=$(aws stepfunctions describe-execution --execution-arn "$EX" \
    --query status --output text)
  [ "$STATUS" != "RUNNING" ] && break
  printf '.'
done
echo

echo "execution : $STATUS"
echo "ACL after : [$(aws s3api get-bucket-acl --bucket "$B" --query 'Grants[].Grantee.URI' --output text)]"
echo "audit log (latest 3):"
aws dynamodb scan --table-name cloud-soar-audit \
  --query "Items[].[timestamp.S,status.S]" --output text | sort | tail -3
