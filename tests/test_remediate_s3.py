import boto3
import pytest

import remediate_s3
from conftest import audit_items


def _event(bucket):
    return {
        "id": "evt-1",
        "detail": {
            "eventName": "PutBucketAcl",
            "requestParameters": {"bucketName": bucket},
        },
    }


def _public_bucket(name):
    s3 = boto3.client("s3")
    s3.create_bucket(
        Bucket=name,
        CreateBucketConfiguration={"LocationConstraint": "ap-south-1"},
    )
    s3.put_bucket_acl(Bucket=name, ACL="public-read")
    return s3


def test_event_without_bucket_is_ignored():
    assert remediate_s3.handler({"detail": {}}, None) == {"status": "ignored"}


def test_public_bucket_is_made_private_and_audited(aws):
    s3 = _public_bucket("soar-test-bucket")

    result = remediate_s3.handler(_event("soar-test-bucket"), None)

    assert result["status"] == "success"
    grants = s3.get_bucket_acl(Bucket="soar-test-bucket")["Grants"]
    assert all("URI" not in g["Grantee"] for g in grants)
    block = s3.get_public_access_block(Bucket="soar-test-bucket")["PublicAccessBlockConfiguration"]
    assert all(block.values())

    items = audit_items()
    assert len(items) == 1
    assert items[0]["status"]["S"] == "success"
    assert items[0]["resource"]["S"] == "s3://soar-test-bucket"
    assert items[0]["trigger"]["S"] == "PutBucketAcl"


def test_missing_bucket_is_audited_as_failed_and_reraised(aws):
    with pytest.raises(Exception):
        remediate_s3.handler(_event("does-not-exist"), None)

    items = audit_items()
    assert len(items) == 1
    assert items[0]["status"]["S"] == "failed"
