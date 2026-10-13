import json
import logging
import os
import uuid
from datetime import UTC, datetime

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)


def _client(service):
    endpoint = os.environ.get("AWS_ENDPOINT_URL")
    host = os.environ.get("LOCALSTACK_HOSTNAME")
    if not endpoint and host:
        endpoint = f"http://{host}:{os.environ.get('EDGE_PORT', '4566')}"
    if endpoint:
        return boto3.client(service, endpoint_url=endpoint)
    return boto3.client(service)


def _audit(record):
    item = {k: {"S": str(v)} for k, v in record.items()}
    _client("dynamodb").put_item(TableName=os.environ["AUDIT_TABLE"], Item=item)


def handler(event, context):
    detail = event.get("detail", {})
    key_details = (detail.get("resource") or {}).get("accessKeyDetails") or {}
    user = key_details.get("userName")
    key_id = key_details.get("accessKeyId")
    if not user or not key_id:
        log.warning("No accessKeyDetails in event, ignoring")
        return {"status": "ignored"}

    record = {
        "audit_id": str(uuid.uuid4()),
        "timestamp": datetime.now(UTC).isoformat(),
        "action": "disable_access_key",
        "resource": f"iam:user/{user}/{key_id}",
        "trigger": detail.get("type", "unknown"),
        "actor": "cloud-soar-disable-key",
        "source_event_id": event.get("id", "unknown"),
    }

    try:
        _client("iam").update_access_key(
            UserName=user, AccessKeyId=key_id, Status="Inactive"
        )
        record["status"] = "success"
    except Exception as e:
        record["status"] = "failed"
        record["error"] = str(e)
        _audit(record)
        raise

    _audit(record)
    log.info(json.dumps(record))
    return record
