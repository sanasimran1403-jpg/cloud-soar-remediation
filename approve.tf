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
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "approve" {
  function_name    = "${var.project}-approve"
  role             = aws_iam_role.approve.arn
  handler          = "approve.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.approve.output_path
  source_code_hash = data.archive_file.approve.output_base64sha256
  timeout          = 15
}

resource "aws_lambda_function_url" "approve" {
  function_name      = aws_lambda_function.approve.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "approve_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.approve.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}
