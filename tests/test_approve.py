import approve


class FakeSfn:
    def __init__(self, fail=False):
        self.calls = []
        self.fail = fail

    def send_task_success(self, **kwargs):
        if self.fail:
            raise RuntimeError("boom")
        self.calls.append(("success", kwargs))

    def send_task_failure(self, **kwargs):
        if self.fail:
            raise RuntimeError("boom")
        self.calls.append(("failure", kwargs))


def _event(**params):
    return {"queryStringParameters": params, "headers": {"user-agent": "pytest"}}


def _use(monkeypatch, fake):
    monkeypatch.setattr(approve, "_sfn", lambda: fake)


def test_unknown_action_is_rejected(monkeypatch):
    fake = FakeSfn()
    _use(monkeypatch, fake)
    resp = approve.handler(_event(action="nuke", token="t1", confirm="1"), None)
    assert resp["statusCode"] == 400
    assert fake.calls == []


def test_missing_token_is_rejected(monkeypatch):
    fake = FakeSfn()
    _use(monkeypatch, fake)
    resp = approve.handler(_event(action="approve", confirm="1"), None)
    assert resp["statusCode"] == 400
    assert fake.calls == []


def test_plain_link_only_shows_confirmation_page(monkeypatch):
    fake = FakeSfn()
    _use(monkeypatch, fake)
    resp = approve.handler(_event(action="approve", token="t1"), None)
    assert resp["statusCode"] == 200
    assert "confirm=1" in resp["body"]
    assert fake.calls == []  # a link previewer must not trigger anything


def test_confirmed_approve_sends_task_success(monkeypatch):
    fake = FakeSfn()
    _use(monkeypatch, fake)
    resp = approve.handler(_event(action="approve", token="t1", confirm="1"), None)
    assert resp["statusCode"] == 200
    assert fake.calls[0][0] == "success"
    assert fake.calls[0][1]["taskToken"] == "t1"


def test_confirmed_deny_sends_task_failure_with_denied_error(monkeypatch):
    fake = FakeSfn()
    _use(monkeypatch, fake)
    resp = approve.handler(_event(action="deny", token="t1", confirm="1"), None)
    assert resp["statusCode"] == 200
    assert fake.calls[0][0] == "failure"
    assert fake.calls[0][1]["error"] == "Denied"


def test_expired_or_used_token_returns_conflict(monkeypatch):
    _use(monkeypatch, FakeSfn(fail=True))
    resp = approve.handler(_event(action="approve", token="t1", confirm="1"), None)
    assert resp["statusCode"] == 409
