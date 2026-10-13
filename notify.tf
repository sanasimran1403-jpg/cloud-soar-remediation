data "archive_file" "notify" {
  type        = "zip"
  source_file = "${path.module}/lambda/notify_slack.py"
  output_path = "${path.module}/lambda/notify_slack.zip"
}

resource "aws_iam_role" "notify" {
  name = "${var.project}-notify-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "notify" {
  name = "${var.project}-notify-policy"
  role = aws_iam_role.notify.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/${var.project}-*:*"
    }]
  })
}

resource "aws_lambda_function" "notify" {
  #checkov:skip=CKV_AWS_117: The function only calls the Slack webhook and AWS APIs. A VPC would add NAT egress without isolating anything useful.
  #checkov:skip=CKV_AWS_272: Code signing is out of scope for this project. Code ships through reviewed CI.
  #checkov:skip=CKV_AWS_173: Default Lambda environment encryption is used. Roadmap: move the webhook URL to Secrets Manager with a customer-managed key.
  function_name    = "${var.project}-notify"
  role             = aws_iam_role.notify.arn
  handler          = "notify_slack.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.notify.output_path
  source_code_hash = data.archive_file.notify.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_iam_role_policy.lambda_baseline]
  timeout    = 15

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      APPROVAL_URL      = aws_lambda_function_url.approve.function_url
    }
  }
}
