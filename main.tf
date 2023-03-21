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
/*
*
* S3
*
*/
# Create the bucket
resource "aws_s3_bucket" "main" {
  bucket = "resume.${var.domain}"
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
  url = "https://raw.githubusercontent.com/braheezy-resume/resume/main/resume.html"
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
