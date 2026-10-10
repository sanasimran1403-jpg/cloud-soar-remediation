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
      Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "notify" {
  function_name    = "${var.project}-notify"
  role             = aws_iam_role.notify.arn
  handler          = "notify_slack.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.notify.output_path
  source_code_hash = data.archive_file.notify.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      APPROVAL_URL      = aws_lambda_function_url.approve.function_url
    }
  }
}
