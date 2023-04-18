output "api_endpoint" {
  value = aws_apigatewayv2_api.lambda.api_endpoint
}
output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.main.id
}
