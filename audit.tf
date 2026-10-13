resource "aws_dynamodb_table" "audit" {
  #checkov:skip=CKV_AWS_119: AWS-owned encryption at rest is on by default. Roadmap: customer-managed key.
  name         = "${var.project}-audit"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "audit_id"

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = "audit_id"
    type = "S"
  }
}

resource "aws_iam_role_policy" "audit" {
  name = "${var.project}-audit-policy"
  role = aws_iam_role.remediate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem"]
      Resource = aws_dynamodb_table.audit.arn
    }]
  })
}
