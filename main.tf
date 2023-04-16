terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.59.0"
    }
  }
}
/*
*
* Variables
*
*/
variable "aws_region" {
  type = string
}
variable "tag_name" {
  type = string
}
variable "domain" {
  type = string
}
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Name = var.tag_name
    }
  }
}
# The ACM cert for Cloudfront must be in US-EAST-1
provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
  default_tags {
    tags = {
      Name = var.tag_name
    }
  }
}
resource "random_string" "random" {
  length  = 4
  special = false
}
/*
*
* S3
*
*/
# Create the bucket
resource "aws_s3_bucket" "main" {
  bucket        = "resume.${var.domain}"
  force_destroy = true
}
# Attach proper permissions for static websites
resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id
  policy = <<-POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::${aws_s3_bucket.main.id}/*"
            ]
        }
    ]
}
POLICY
}
# Require for static website
resource "aws_s3_bucket_website_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  index_document {
    suffix = "resume.html"
  }
}
# Download the latest resume, for upload
# This is only for the first deployment, not how every resume update is deployed
data "http" "resume" {
  url = "https://github.com/braheezy-resume/resume/releases/latest/download/resume.html"
}
# Upload resume to bucket
resource "aws_s3_object" "object" {
  bucket  = aws_s3_bucket.main.bucket
  key     = "resume.html"
  content = data.http.resume.response_body
  # Needed so the page renders in browser instead of downloading
  content_type = "text/html"

  etag = md5(data.http.resume.response_body)
}
/*
*
* ACM
*
*/
# Ask ACM for a certficate, enabling HTTPS with CloudFront
# Can't use the builtin CloudFront cert b/c of custom domain
resource "aws_acm_certificate" "main" {
  provider          = aws.us-east-1
  domain_name       = var.domain
  validation_method = "DNS"

  # Add wildcard name, to cover all sub-domains too
  subject_alternative_names = [
    "*.${var.domain}"
  ]

  lifecycle {
    create_before_destroy = true
  }
}
# Wait for the cert to be issued
resource "aws_acm_certificate_validation" "main" {
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.dns_validation : record.fqdn]
}
/*
*
* Route 53
*
*/
# Create main hosted zone
# This is created for you by Route 53 when you buy a domain. I deleted that...caused a bunch of issues
resource "aws_route53_zone" "main" {
  name = var.domain
}
# Create all the records required to validate we own the domain
# for the certs we just required from ACM
resource "aws_route53_record" "dns_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}
/*
*
* CloudFront
*
*/
# Create the CloudFront distro
resource "aws_cloudfront_distribution" "main" {
  origin {
    origin_id   = aws_s3_bucket_website_configuration.main.website_endpoint
    domain_name = aws_s3_bucket.main.bucket_regional_domain_name
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "resume.html"

  #* The friendly name to show instead of the auto-generated cloudfront name
  aliases = [aws_s3_bucket.main.id]

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket_website_configuration.main.website_endpoint
    viewer_protocol_policy = "allow-all"
    # Using the CachingOptimized managed policy ID:
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # The cheapest class. Only US, UK, and Canada
  price_class = "PriceClass_100"
  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }
  #* Use our custom SSL cert b/c of custom domain name
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.main.arn
    ssl_support_method  = "sni-only"
  }
}
# Create alias record to route requests CloudFront name
resource "aws_route53_record" "a" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "resume.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
/*
*
* DynamoDB
*
*/
resource "aws_dynamodb_table" "main" {
  name           = "site-analytics"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "metrics"

  attribute {
    name = "metrics"
    type = "S"
  }
}
resource "aws_dynamodb_table_item" "init" {
  table_name = aws_dynamodb_table.main.name
  hash_key   = aws_dynamodb_table.main.hash_key

  item = <<ITEM
{
  "metrics": {"S": "resume.${var.domain}"},
  "visitorCount": {"N": "0"}
}
ITEM
}
/*
*
* Lambda
*
*/
resource "aws_s3_bucket" "lambda_bucket" {
  bucket_prefix = "resume-lambda"
  force_destroy = true
}
resource "aws_s3_bucket_acl" "private_bucket" {
  bucket = aws_s3_bucket.lambda_bucket.id
  acl    = "private"
}
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambdaDBAccess"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Sid    = ""
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      }
    ]
  })
}
resource "aws_iam_policy" "lambda_exec" {
  name = "lambda-db-access-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Scan",
        "dynamodb:DescribeTable"
      ]
      Resource = "arn:aws:dynamodb:*:*:table/${aws_dynamodb_table.main.name}"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_exec.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/src.zip"

  source {
    content  = "hello"
    filename = "dummy"
  }
}
resource "aws_lambda_function" "count" {
  function_name = "count"
  description   = "Handle logic to get/update visitor count to resume.${var.domain}"

  filename = data.archive_file.lambda_zip.output_path

  runtime = "go1.x"
  handler = "count"

  role = aws_iam_role.lambda_exec_role.arn

  environment {
    variables = {
      DDB_TABLE = aws_dynamodb_table.main.name
    }
  }
  depends_on = [aws_cloudwatch_log_group.lambda_logs]

}
resource "aws_lambda_function_url" "count" {
  function_name      = aws_lambda_function.count.function_name
  authorization_type = "AWS_IAM"
}
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name = "/aws/lambda/resume-analytics"

  retention_in_days = 7
}
/*
*
* API Gateway
*
*/
resource "aws_apigatewayv2_api" "lambda" {
  name          = "resume-api"
  protocol_type = "HTTP"
}
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.lambda.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
  depends_on = [aws_cloudwatch_log_group.api_gw]
}
resource "aws_apigatewayv2_integration" "apigw_lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.count.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}
resource "aws_apigatewayv2_route" "post" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "POST /count"
  target    = "integrations/${aws_apigatewayv2_integration.apigw_lambda.id}"
}
resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/resume-api"

  retention_in_days = 7
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.count.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}
