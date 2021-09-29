terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.48.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
  }

  required_version = "~> 1.0"
}

data "aws_caller_identity" "current" {}

locals {
  name        = "sitemap-generator-tf"
  environment = "dev"
  region      = "ap-northeast-1"
  account_id  = data.aws_caller_identity.current.account_id
}

provider "aws" {
  region = local.region
}

resource "aws_s3_bucket" "sitemap_generator_assets_bucket" {
  bucket        = local.name
  acl           = "private"
  force_destroy = true
}

resource "aws_s3_bucket_object" "glue_job_script" {
  bucket = aws_s3_bucket.sitemap_generator_assets_bucket.id
  key    = "sitemap_generator_glue.py"
  source = "sitemap_generator_glue.py"
  etag   = filemd5("sitemap_generator_glue.py")
}

resource "aws_glue_job" "sitemap_generator_glue" {
  name              = local.name
  glue_version      = "3.0"
  max_retries       = 0
  worker_type       = "G.1X"
  number_of_workers = 2
  # Set your gule role here.
  role_arn          = "arn:aws:iam::XXXX:role/glue-XXXX_role"
  timeout           = 2880

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket_object.glue_job_script.bucket}/${aws_s3_bucket_object.glue_job_script.key}"
    python_version  = 3
  }

  default_arguments = {
    "--class"                           = "GlueApp"
    "--job-language"                    = "python"
    "--additional-python-modules"       = "sitemap-generator==0.9.8, slack-sdk==3.11.0"
    "--python-modules-installer-option" = "--upgrade"
  }

  tags = {
    "category"   = "internal-tool"
    "department" = "autostream"
  }
}

resource "null_resource" "pip_install_requirements" {
  provisioner "local-exec" {
    command = "docker build . -t bundle-pip-modules-for-aws-lambda-layers:python3.8 && source install-requirements.sh"
  }
}

resource "aws_lambda_layer_version" "sitemap_generator_utils" {
  depends_on          = [null_resource.pip_install_requirements]
  filename            = "layer.zip"
  layer_name          = "sitemap-generator-utils"
  compatible_runtimes = ["python3.8"]
}

data "archive_file" "lambda_function" {
  type        = "zip"
  source_dir  = "lambda_function"
  output_path = "lambda_function/lambda_function.zip"
}

resource "aws_lambda_function" "sitemap_generator_lambda" {
  function_name    = local.name
  filename         = data.archive_file.lambda_function.output_path
  runtime          = "python3.8"
  handler          = "sitemap_generator_lambda.lambda_handler"
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  # Set your lambda role here.
  role             = "arn:aws:iam::XXXX:role/lambda-XXXX-role"
  layers           = [aws_lambda_layer_version.sitemap_generator_utils.arn]
  timeout          = 30
}

resource "aws_api_gateway_rest_api" "api" {
  name = local.name
}

resource "aws_api_gateway_resource" "endpoint" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "slack"
}

resource "aws_api_gateway_method" "endpoint" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.endpoint.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "endpoint" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.endpoint.id
  http_method = aws_api_gateway_method.endpoint.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration" "endpoint" {
  depends_on              = [aws_api_gateway_method.endpoint, aws_api_gateway_method_response.endpoint]
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_method.endpoint.resource_id
  http_method             = aws_api_gateway_method.endpoint.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.sitemap_generator_lambda.invoke_arn
}

resource "aws_api_gateway_integration_response" "endpoint" {
  depends_on  = [aws_api_gateway_integration.endpoint]
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.endpoint.id
  http_method = aws_api_gateway_method.endpoint.http_method
  status_code = aws_api_gateway_method_response.endpoint.status_code

  response_templates = {
    "application/json" = ""
  }
}

resource "aws_api_gateway_deployment" "api" {
  depends_on  = [aws_api_gateway_integration_response.endpoint]
  rest_api_id = aws_api_gateway_rest_api.api.id
  description = "Deployed endpoint at ${timestamp()}"
}

resource "aws_api_gateway_stage" "api" {
  stage_name    = local.environment
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api.id
}

resource "aws_lambda_permission" "api" {
  statement_id  = "${local.name}-AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = local.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${local.region}:${local.account_id}:${aws_api_gateway_rest_api.api.id}/*/${aws_api_gateway_method.endpoint.http_method}${aws_api_gateway_resource.endpoint.path}"
}
