terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}
resource "aws_dynamodb_table" "visitor_count" {
  name         = "visitor-count-tf"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Project   = "Cloud Resume Terraform"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "resume-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "resume-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "dynamodb:UpdateItem"
        ]

        Resource = aws_dynamodb_table.visitor_count.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "resume_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "resume-lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitor_count.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_dynamodb
  ]
}
resource "aws_apigatewayv2_api" "resume_api" {
  name          = "resume-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_integration" "resume_lambda" {
  api_id = aws_apigatewayv2_api.resume_api.id

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.resume_lambda.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "resume_route" {
  api_id = aws_apigatewayv2_api.resume_api.id

  route_key = "GET /resume"
  target    = "integrations/${aws_apigatewayv2_integration.resume_lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id = aws_apigatewayv2_api.resume_api.id

  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowResumeApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resume_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.resume_api.execution_arn}/*/*"
}