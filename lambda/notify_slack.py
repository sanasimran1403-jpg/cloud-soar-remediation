import json
import os
import urllib.request
from urllib.parse import quote


def handler(event, context):
    resource = event.get("resource") or f"s3://{event.get('bucket', 'unknown')}"
    lines = [
        f":rotating_light: *Cloud SOAR*: {event.get('title', 'Security finding')}",
        f"*Resource:* `{resource}`",
        f"*Trigger:* `{event.get('trigger', 'unknown')}`",
    ]
    if event.get("status"):
        lines.append(f"*Status:* {event['status']}")

    base = os.environ.get("APPROVAL_URL", "").rstrip("/")
    token = event.get("task_token")
    if token and base:
        t = quote(token, safe="")
        lines.append(
            f"<{base}/?action=approve&token={t}|Approve fix>\n"
            f"<{base}/?action=deny&token={t}|Deny>"
        )
        note = event.get("timeout_note", "No response in time = auto-fix.")
        lines.append(f"_{note}_")

    body = json.dumps({"text": "\n".join(lines)}).encode()
    req = urllib.request.Request(
        os.environ["SLACK_WEBHOOK_URL"],
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return {"slack_status": resp.status}
