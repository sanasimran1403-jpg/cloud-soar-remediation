import html
import json
import os
from urllib.parse import quote

import boto3


def _sfn():
    endpoint = os.environ.get("AWS_ENDPOINT_URL")
    host = os.environ.get("LOCALSTACK_HOSTNAME")
    if not endpoint and host:
        endpoint = f"http://{host}:{os.environ.get('EDGE_PORT', '4566')}"
    if endpoint:
        return boto3.client("stepfunctions", endpoint_url=endpoint)
    return boto3.client("stepfunctions")


def _page(status, body):
    # no-referrer keeps the browser from sending Origin/Referer headers,
    # which LocalStack's CORS check rejects for Lambda URL subdomains.
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "text/html; charset=utf-8",
            "Referrer-Policy": "no-referrer",
        },
        "body": (
            "<html><head><meta name='referrer' content='no-referrer'></head>"
            f"<body style='font-family:sans-serif;margin:3em'>{body}</body></html>"
        ),
    }


def handler(event, context):
    params = event.get("queryStringParameters") or {}
    action = params.get("action")
    token = params.get("token")
    print("approval request:", action, "confirm=", params.get("confirm"), "ua=", (event.get("headers") or {}).get("user-agent"))

    if action not in ("approve", "deny") or not token:
        return _page(400, "<h3>Invalid request</h3>")

    # Step 1: a plain link only shows a confirmation page.
    # Link previewers and scanners that fetch the URL cannot trigger the action.
    if params.get("confirm") != "1":
        href = html.escape(
            f"?action={action}&token={quote(token, safe='')}&confirm=1", quote=True
        )
        label = "Approve fix" if action == "approve" else "Deny (leave bucket public)"
        return _page(
            200,
            f"<h3>Cloud SOAR</h3><p>Confirm action: <b>{action}</b></p>"
            f"<a href='{href}' rel='noreferrer' "
            "style='display:inline-block;padding:10px 20px;font-size:16px;"
            "border:1px solid #888;border-radius:4px;background:#eee;"
            f"color:#000;text-decoration:none'>{label}</a>",
        )

    # Step 2: the confirm link was clicked, so perform the action.
    try:
        if action == "approve":
            _sfn().send_task_success(
                taskToken=token, output=json.dumps({"decision": "approved"})
            )
            return _page(200, "<h3>Approved</h3><p>Remediation is running.</p>")
        _sfn().send_task_failure(
            taskToken=token, error="Denied", cause="Denied by human via Slack link"
        )
        return _page(200, "<h3>Denied</h3><p>No action taken. Decision recorded.</p>")
    except Exception as e:
        print("approval error:", e)
        return _page(409, "<h3>Could not process</h3><p>Link expired or already used.</p>")
