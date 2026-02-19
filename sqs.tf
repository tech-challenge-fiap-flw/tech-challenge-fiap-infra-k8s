# SQS FIFO Queues for microservices communication

resource "aws_sqs_queue" "os_events" {
  name                        = "tc-fiap-os-events-${var.environment}.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  deduplication_scope         = "queue"
  fifo_throughput_limit       = "perQueue"

  tags = {
    Name        = "tc-fiap-os-events-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_sqs_queue" "billing_events" {
  name                        = "tc-fiap-billing-events-${var.environment}.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  deduplication_scope         = "queue"
  fifo_throughput_limit       = "perQueue"

  tags = {
    Name        = "tc-fiap-billing-events-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_sqs_queue" "execution_events" {
  name                        = "tc-fiap-execution-events-${var.environment}.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  deduplication_scope         = "queue"
  fifo_throughput_limit       = "perQueue"

  tags = {
    Name        = "tc-fiap-execution-events-${var.environment}"
    Environment = var.environment
  }
}
