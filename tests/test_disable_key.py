import boto3
import pytest

import disable_key
from conftest import audit_items


def _finding(user, key_id):
    return {
        "id": "finding-1",
        "detail": {
            "type": "UnauthorizedAccess:IAMUser/MaliciousIPCaller.Custom",
            "resource": {
                "accessKeyDetails": {"userName": user, "accessKeyId": key_id}
            },
        },
    }


def test_event_without_key_details_is_ignored():
    assert disable_key.handler({"detail": {}}, None) == {"status": "ignored"}


def test_key_is_disabled_not_deleted_and_audited(aws):
    iam = boto3.client("iam")
    iam.create_user(UserName="alice")
    key_id = iam.create_access_key(UserName="alice")["AccessKey"]["AccessKeyId"]

    result = disable_key.handler(_finding("alice", key_id), None)

    assert result["status"] == "success"
    keys = iam.list_access_keys(UserName="alice")["AccessKeyMetadata"]
    assert len(keys) == 1
    assert keys[0]["Status"] == "Inactive"

    items = audit_items()
    assert items[0]["action"]["S"] == "disable_access_key"
    assert items[0]["status"]["S"] == "success"


def test_unknown_user_is_audited_as_failed_and_reraised(aws):
    with pytest.raises(Exception):
        disable_key.handler(_finding("nobody", "AKIAFAKEFAKEFAKE1234"), None)

    assert audit_items()[0]["status"]["S"] == "failed"
