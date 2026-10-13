# Shared hardening: dead-letter queue, baseline Lambda permissions,
# Step Functions logging and tracing.

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project}-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

locals {
  lambda_roles = {
    remediate   = aws_iam_role.remediate.id
    notify      = aws_iam_role.notify.id
    approve     = aws_iam_role.approve.id
    disable_key = aws_iam_role.disable_key.id
  }
}

resource "aws_iam_role_policy" "lambda_baseline" {
  for_each = local.lambda_roles

  name = "${var.project}-${each.key}-baseline"
  role = each.value
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.dlq.arn
      },
      {
        # X-Ray write actions do not support resource-level permissions.
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "sfn" {
  #checkov:skip=CKV_AWS_158: Logs hold errors only because include_execution_data is false. Roadmap: customer-managed key.
  name              = "/aws/vendedlogs/states/${var.project}"
  retention_in_days = 365
}

resource "aws_iam_role_policy" "sfn_observability" {
  name = "${var.project}-sfn-observability"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Log delivery and X-Ray actions do not support resource-level permissions.
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments", "xray:PutTelemetryRecords",
          "xray:GetSamplingRules", "xray:GetSamplingTargets"
        ]
        Resource = "*"
      }
    ]
  })
}
