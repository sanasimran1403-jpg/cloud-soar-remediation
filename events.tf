resource "aws_iam_role" "events_sfn" {
  name = "${var.project}-events-sfn-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "events.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "events_sfn" {
  name = "${var.project}-events-sfn-policy"
  role = aws_iam_role.events_sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = aws_sfn_state_machine.soar.arn
    }]
  })
}

resource "aws_cloudwatch_event_target" "sfn" {
  rule     = aws_cloudwatch_event_rule.s3_public.name
  arn      = aws_sfn_state_machine.soar.arn
  role_arn = aws_iam_role.events_sfn.arn
}
