import json
import urllib.request

import notify_slack


class FakeResponse:
    status = 200

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def _capture(monkeypatch):
    sent = {}

    def fake_urlopen(req, timeout=0):
        sent["body"] = json.loads(req.data.decode())
        return FakeResponse()

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)
    return sent


def _env(monkeypatch):
    monkeypatch.setenv("SLACK_WEBHOOK_URL", "https://example.invalid/hook")
    monkeypatch.setenv("APPROVAL_URL", "https://approve.example.invalid/")


def test_message_with_task_token_contains_both_links(monkeypatch):
    _env(monkeypatch)
    sent = _capture(monkeypatch)

    result = notify_slack.handler(
        {"bucket": "b1", "trigger": "PutBucketAcl", "task_token": "a/b+c"}, None
    )

    text = sent["body"]["text"]
    assert result == {"slack_status": 200}
    assert "s3://b1" in text
    assert "action=approve" in text and "action=deny" in text
    assert "a%2Fb%2Bc" in text  # the token must be URL-encoded


def test_message_without_task_token_has_no_links(monkeypatch):
    _env(monkeypatch)
    sent = _capture(monkeypatch)

    notify_slack.handler({"resource": "iam:user/alice/AKIA1", "status": "success"}, None)

    text = sent["body"]["text"]
    assert "iam:user/alice/AKIA1" in text
    assert "action=approve" not in text
