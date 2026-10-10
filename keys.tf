data "archive_file" "disable_key" {
  type        = "zip"
  source_file = "${path.module}/lambda/disable_key.py"
  output_path = "${path.module}/lambda/disable_key.zip"
}

resource "aws_iam_role" "disable_key" {
  name = "${var.project}-disable-key-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "disable_key" {
  name = "${var.project}-disable-key-policy"
  role = aws_iam_role.disable_key.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:UpdateAccessKey"]
        Resource = "arn:aws:iam::*:user/*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.audit.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "disable_key" {
  function_name    = "${var.project}-disable-key"
  role             = aws_iam_role.disable_key.arn
  handler          = "disable_key.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.disable_key.output_path
  source_code_hash = data.archive_file.disable_key.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      AUDIT_TABLE = aws_dynamodb_table.audit.name
    }
  }
}
