terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.59.0"
    }
  }
}
variable "aws_region" {
  type = string
}
variable "tag_name" {
  type = string
}
variable "domain" {
  default = "braheezy.net"
}
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Name = var.tag_name
    }
  }
}
provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
  default_tags {
    tags = {
      Name = var.tag_name
    }
  }
}
resource "aws_s3_bucket" "main" {
  bucket = "resume.${var.domain}"
}
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
resource "aws_s3_bucket_website_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  index_document {
    suffix = "resume.html"
  }
}
data "http" "resume" {
  url = "https://raw.githubusercontent.com/braheezy-resume/resume/main/resume.html"
}
resource "aws_s3_object" "object" {
  bucket       = aws_s3_bucket.main.bucket
  key          = "resume.html"
  content      = data.http.resume.response_body
  content_type = "text/html"

  etag = md5(data.http.resume.response_body)
}
resource "aws_acm_certificate" "main" {
  provider          = aws.us-east-1
  domain_name       = var.domain
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.domain}"
  ]

  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_acm_certificate_validation" "main" {
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cname : record.fqdn]
}
resource "aws_route53_zone" "main" {
  name = var.domain
}
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
resource "aws_route53_record" "cname" {
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
resource "aws_cloudfront_distribution" "main" {
  origin {
    origin_id   = aws_s3_bucket_website_configuration.main.website_endpoint
    domain_name = aws_s3_bucket.main.bucket_regional_domain_name
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "resume.html"

  aliases = [aws_s3_bucket.main.id]

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket_website_configuration.main.website_endpoint
    viewer_protocol_policy = "allow-all"
    # Using the CachingOptimized managed policy ID:
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  price_class = "PriceClass_100"
  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.main.arn
    ssl_support_method  = "sni-only"
  }
}
