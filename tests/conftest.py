import sys
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

# The Lambda sources live in ./lambda, which is not a package.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lambda"))


@pytest.fixture(autouse=True)
def aws_env(monkeypatch):
    # Make sure no test can reach LocalStack or a real account.
    monkeypatch.delenv("AWS_ENDPOINT_URL", raising=False)
    monkeypatch.delenv("LOCALSTACK_HOSTNAME", raising=False)
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "ap-south-1")
    monkeypatch.setenv("AUDIT_TABLE", "audit-test")


@pytest.fixture
def aws():
    """Mocked AWS with an empty audit table."""
    with mock_aws():
        boto3.client("dynamodb").create_table(
            TableName="audit-test",
            KeySchema=[{"AttributeName": "audit_id", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "audit_id", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        yield


def audit_items():
    return boto3.client("dynamodb").scan(TableName="audit-test")["Items"]
