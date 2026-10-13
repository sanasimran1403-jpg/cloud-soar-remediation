data "archive_file" "approve" {
  type        = "zip"
  source_file = "${path.module}/lambda/approve.py"
  output_path = "${path.module}/lambda/approve.zip"
}

resource "aws_iam_role" "approve" {
  name = "${var.project}-approve-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "approve" {
  name = "${var.project}-approve-policy"
  role = aws_iam_role.approve.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["states:SendTaskSuccess", "states:SendTaskFailure"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/${var.project}-*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "approve" {
  #checkov:skip=CKV_AWS_117: The function only calls the Slack webhook and AWS APIs. A VPC would add NAT egress without isolating anything useful.
  #checkov:skip=CKV_AWS_272: Code signing is out of scope for this project. Code ships through reviewed CI.
  function_name    = "${var.project}-approve"
  role             = aws_iam_role.approve.arn
  handler          = "approve.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.approve.output_path
  source_code_hash = data.archive_file.approve.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_iam_role_policy.lambda_baseline]
  timeout    = 15
}

resource "aws_lambda_function_url" "approve" {
  #checkov:skip=CKV_AWS_258: Slack approval links must work without AWS credentials. Access is gated by an unguessable single-use task token plus a confirmation step.
  function_name      = aws_lambda_function.approve.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "approve_url" {
  #checkov:skip=CKV_AWS_301: Public by design for Slack approval links. See the function URL note.
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.approve.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
