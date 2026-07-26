output "resume_api_url" {
  description = "Public URL for the Terraform-created resume API"
  value       = "${aws_apigatewayv2_api.resume_api.api_endpoint}/resume"
}