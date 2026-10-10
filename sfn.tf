resource "aws_iam_role" "sfn" {
  name = "${var.project}-sfn-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "sfn" {
  name = "${var.project}-sfn-policy"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [aws_lambda_function.remediate.arn, aws_lambda_function.notify.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.audit.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "soar" {
  name     = "${var.project}-s3-flow"
  role_arn = aws_iam_role.sfn.arn

  definition = jsonencode({
    Comment = "S3 exposure: ask for approval, auto-fix on timeout"
    StartAt = "NotifyAndWait"
    States = {
      NotifyAndWait = {
        Type           = "Task"
        Resource       = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        TimeoutSeconds = var.approval_timeout
        Parameters = {
          FunctionName = aws_lambda_function.notify.arn
          Payload = {
            "title"        = "Public S3 bucket detected: approval needed"
            "bucket.$"     = "$.detail.requestParameters.bucketName"
            "trigger.$"    = "$.detail.eventName"
            "task_token.$" = "$$.Task.Token"
          }
        }
        ResultPath = "$.approval"
        Catch = [
          { ErrorEquals = ["Denied"], ResultPath = "$.approval", Next = "RecordDenied" },
          { ErrorEquals = ["States.ALL"], ResultPath = "$.approval", Next = "Remediate" }
        ]
        Next = "Remediate"
      }

      Remediate = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.remediate.arn
          "Payload.$"  = "$"
        }
        ResultPath = "$.remediation"
        Next       = "NotifyResult"
      }

      NotifyResult = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.notify.arn
          Payload = {
            "title"     = "Bucket auto-remediated"
            "bucket.$"  = "$.detail.requestParameters.bucketName"
            "trigger.$" = "$.detail.eventName"
            "status.$"  = "$.remediation.Payload.status"
          }
        }
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.notify_error", Next = "Done" }]
        Next  = "Done"
      }

      Done = {
        Type = "Succeed"
      }

      RecordDenied = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.audit.name
          Item = {
            "audit_id"  = { "S.$" = "$$.Execution.Name" }
            "timestamp" = { "S.$" = "$$.State.EnteredTime" }
            "action"    = { "S" = "block_public_access" }
            "resource"  = { "S.$" = "States.Format('s3://{}', $.detail.requestParameters.bucketName)" }
            "trigger"   = { "S.$" = "$.detail.eventName" }
            "status"    = { "S" = "denied_by_human" }
          }
        }
        End = true
      }
    }
  })
}
