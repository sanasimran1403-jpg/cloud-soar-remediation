resource "aws_iam_role_policy" "sfn_keys" {
  name = "${var.project}-sfn-keys-policy"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = [aws_lambda_function.disable_key.arn]
    }]
  })
}

resource "aws_sfn_state_machine" "keys" {
  name     = "${var.project}-key-flow"
  role_arn = aws_iam_role.sfn.arn

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  tracing_configuration {
    enabled = true
  }
  depends_on = [aws_iam_role_policy.sfn_keys]

  definition = jsonencode({
    Comment = "Leaked IAM access key: ask for approval, never act on timeout"
    StartAt = "NotifyAndWait"
    States = {
      NotifyAndWait = {
        Type           = "Task"
        Resource       = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        TimeoutSeconds = var.key_approval_timeout
        Parameters = {
          FunctionName = aws_lambda_function.notify.arn
          Payload = {
            "title"        = "Possible leaked IAM access key: approval needed"
            "resource.$"   = "States.Format('iam:user/{}/{}', $.detail.resource.accessKeyDetails.userName, $.detail.resource.accessKeyDetails.accessKeyId)"
            "trigger.$"    = "$.detail.type"
            "timeout_note" = "No response in time = NO action. The key stays active until a human decides."
            "task_token.$" = "$$.Task.Token"
          }
        }
        ResultPath = "$.approval"
        Catch = [
          { ErrorEquals = ["Denied"], ResultPath = "$.approval", Next = "RecordDenied" },
          { ErrorEquals = ["States.ALL"], ResultPath = "$.approval", Next = "RecordNoAction" }
        ]
        Next = "DisableKey"
      }

      DisableKey = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.disable_key.arn
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
            "title"      = "Access key disabled"
            "resource.$" = "States.Format('iam:user/{}/{}', $.detail.resource.accessKeyDetails.userName, $.detail.resource.accessKeyDetails.accessKeyId)"
            "trigger.$"  = "$.detail.type"
            "status.$"   = "$.remediation.Payload.status"
          }
        }
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.notify_error", Next = "Done" }]
        Next  = "Done"
      }

      RecordDenied = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.audit.name
          Item = {
            "audit_id"  = { "S.$" = "$$.Execution.Name" }
            "timestamp" = { "S.$" = "$$.State.EnteredTime" }
            "action"    = { "S" = "disable_access_key" }
            "resource"  = { "S.$" = "States.Format('iam:user/{}/{}', $.detail.resource.accessKeyDetails.userName, $.detail.resource.accessKeyDetails.accessKeyId)" }
            "trigger"   = { "S.$" = "$.detail.type" }
            "status"    = { "S" = "denied_by_human" }
          }
        }
        Next = "Done"
      }

      RecordNoAction = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.audit.name
          Item = {
            "audit_id"  = { "S.$" = "$$.Execution.Name" }
            "timestamp" = { "S.$" = "$$.State.EnteredTime" }
            "action"    = { "S" = "disable_access_key" }
            "resource"  = { "S.$" = "States.Format('iam:user/{}/{}', $.detail.resource.accessKeyDetails.userName, $.detail.resource.accessKeyDetails.accessKeyId)" }
            "trigger"   = { "S.$" = "$.detail.type" }
            "status"    = { "S" = "no_action_timeout" }
          }
        }
        Next = "NotifyNoAction"
      }

      NotifyNoAction = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.notify.arn
          Payload = {
            "title"      = "No response: access key left ACTIVE, manual review needed"
            "resource.$" = "States.Format('iam:user/{}/{}', $.detail.resource.accessKeyDetails.userName, $.detail.resource.accessKeyDetails.accessKeyId)"
            "trigger.$"  = "$.detail.type"
            "status"     = "no action taken"
          }
        }
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.notify_error", Next = "Done" }]
        Next  = "Done"
      }

      Done = {
        Type = "Succeed"
      }
    }
  })
}

resource "aws_cloudwatch_event_rule" "key_leak" {
  name        = "${var.project}-key-leak-detect"
  description = "GuardDuty finding involving an IAM user access key"

  event_pattern = jsonencode({
    source        = ["aws.guardduty", "soar.simulator"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      type = [{ prefix = "UnauthorizedAccess:IAMUser/" }]
      resource = {
        resourceType = ["AccessKey"]
        accessKeyDetails = {
          userType = ["IAMUser"]
        }
      }
    }
  })
}

resource "aws_iam_role_policy" "events_sfn_keys" {
  name = "${var.project}-events-sfn-keys-policy"
  role = aws_iam_role.events_sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = aws_sfn_state_machine.keys.arn
    }]
  })
}

resource "aws_cloudwatch_event_target" "key_flow" {
  rule     = aws_cloudwatch_event_rule.key_leak.name
  arn      = aws_sfn_state_machine.keys.arn
  role_arn = aws_iam_role.events_sfn.arn
}
