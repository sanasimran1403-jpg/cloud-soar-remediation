# Test bucket that we will make public
resource "aws_s3_bucket" "test" {
  bucket        = "${var.project}-test-bucket"
  force_destroy = true
}

# EventBridge rule: detect API calls that expose an S3 bucket
resource "aws_cloudwatch_event_rule" "s3_public" {
  name        = "${var.project}-s3-public-detect"
  description = "Detect S3 bucket exposure API calls"

  event_pattern = jsonencode({
    source        = ["aws.s3", "soar.simulator"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["PutBucketAcl", "PutBucketPolicy", "DeletePublicAccessBlock"]
    }
  })
}

# ---------- Remediation Lambda ----------
data "archive_file" "remediate" {
  type        = "zip"
  source_file = "${path.module}/lambda/remediate_s3.py"
  output_path = "${path.module}/lambda/remediate_s3.zip"
}

resource "aws_iam_role" "remediate" {
  name = "${var.project}-remediate-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "remediate" {
  name = "${var.project}-remediate-policy"
  role = aws_iam_role.remediate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutBucketPublicAccessBlock", "s3:PutBucketAcl"]
        Resource = var.remediation_bucket_arns
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/${var.project}-*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "remediate" {
  function_name    = "${var.project}-remediate-s3"
  role             = aws_iam_role.remediate.arn
  handler          = "remediate_s3.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.remediate.output_path
  source_code_hash = data.archive_file.remediate.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_iam_role_policy.lambda_baseline]
  timeout    = 30

  environment {
    variables = {
      AUDIT_TABLE = aws_dynamodb_table.audit.name
    }
  }
}

