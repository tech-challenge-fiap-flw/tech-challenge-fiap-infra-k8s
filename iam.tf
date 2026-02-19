# IAM Policy for SQS access from EKS nodes

resource "aws_iam_policy" "sqs_access" {
  name        = "tc-fiap-sqs-access-${var.environment}"
  description = "Allow EKS nodes to access SQS queues"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          aws_sqs_queue.os_events.arn,
          aws_sqs_queue.billing_events.arn,
          aws_sqs_queue.execution_events.arn
        ]
      }
    ]
  })
}
