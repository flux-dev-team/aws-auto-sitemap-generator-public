output "api_url" {
  value = "${aws_api_gateway_stage.api.invoke_url}/${aws_api_gateway_resource.endpoint.path_part}"
}