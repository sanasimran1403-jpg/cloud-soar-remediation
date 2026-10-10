import json
import logging
import os
import uuid
from datetime import datetime, timezone

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
    log.info("audit written: %s", record["audit_id"])


def handler(event, context):
    detail = event.get("detail", {})
    bucket = (detail.get("requestParameters") or {}).get("bucketName")
    if not bucket:
        log.warning("No bucketName in event, ignoring")
        return {"status": "ignored"}

    record = {
        "audit_id": str(uuid.uuid4()),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "action": "block_public_access",
        "resource": f"s3://{bucket}",
        "trigger": detail.get("eventName", "unknown"),
        "actor": (detail.get("userIdentity") or {}).get("arn", "unknown"),
        "source_event_id": event.get("id", "unknown"),
    }

    try:
        s3 = _client("s3")
        s3.put_bucket_acl(Bucket=bucket, ACL="private")
        s3.put_public_access_block(
            Bucket=bucket,
            PublicAccessBlockConfiguration={
                "BlockPublicAcls": True,
                "IgnorePublicAcls": True,
                "BlockPublicPolicy": True,
                "RestrictPublicBuckets": True,
            },
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
