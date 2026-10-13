#!/usr/bin/env bash
# End-to-end test for the leaked access key flow.
# Usage: ./test_key_flow.sh approve|deny|timeout
set -u
export AWS_ENDPOINT_URL=http://localhost:4566
MODE=${1:-approve}
KEYUSER=leaky-test-user

SM=$(aws stepfunctions list-state-machines \
  --query "stateMachines[?name=='cloud-soar-key-flow'].stateMachineArn" --output text)
[ -n "$SM" ] || { echo "State machine not found. Run ./up.sh first."; exit 1; }

# Stop any executions still waiting from earlier runs
for E in $(aws stepfunctions list-executions --state-machine-arn "$SM" \
  --status-filter RUNNING --query "executions[].executionArn" --output text); do
  aws stepfunctions stop-execution --execution-arn "$E" >/dev/null
done

echo "== Creating a fresh access key for $KEYUSER"
aws iam create-user --user-name "$KEYUSER" >/dev/null 2>&1 || true
for K in $(aws iam list-access-keys --user-name "$KEYUSER" \
  --query "AccessKeyMetadata[].AccessKeyId" --output text); do
  aws iam delete-access-key --user-name "$KEYUSER" --access-key-id "$K"
done
KEY=$(aws iam create-access-key --user-name "$KEYUSER" \
  --query AccessKey.AccessKeyId --output text)
echo "key status before: $(aws iam list-access-keys --user-name "$KEYUSER" \
  --query 'AccessKeyMetadata[].Status' --output text)"

python3 - "$KEYUSER" "$KEY" <<'PY' > key_entries.json
import json
import sys

user, key = sys.argv[1], sys.argv[2]
detail = {
    "type": "UnauthorizedAccess:IAMUser/MaliciousIPCaller.Custom",
    "resource": {
        "resourceType": "AccessKey",
        "accessKeyDetails": {
            "userType": "IAMUser",
            "userName": user,
            "accessKeyId": key,
        },
    },
}
print(json.dumps([{
    "Source": "soar.simulator",
    "DetailType": "GuardDuty Finding",
    "Detail": json.dumps(detail),
}]))
PY

aws events put-events --entries file://key_entries.json >/dev/null

if [ "$MODE" = "timeout" ]; then
  echo ">> Do nothing in Slack. The key must stay ACTIVE after the timeout."
else
  echo ">> Open Slack, click '$MODE' in the newest message, then confirm."
fi

echo "== Waiting for the execution to finish (up to 200 seconds)"
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

echo "execution        : $STATUS"
echo "key status after : $(aws iam list-access-keys --user-name "$KEYUSER" \
  --query 'AccessKeyMetadata[].Status' --output text)"
echo "audit log (latest 3):"
aws dynamodb scan --table-name cloud-soar-audit \
  --query "Items[].[timestamp.S,action.S,status.S]" --output text | sort | tail -3
