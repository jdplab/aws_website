terraform {

    backend "remote" {
        organization = "JP-Lab"

        workspaces {
            name = "aws-website_dev"
        }
    }

    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "5.53.0"
        }

        cloudflare = {
            source = "cloudflare/cloudflare"
            version = "4.25.0"
        }

        acme = {
            source = "vancluever/acme"
            version = "2.21.0"
        }
    }
}

provider "aws" {
    access_key = var.AWS_ACCESS_KEY_ID
    secret_key = var.AWS_SECRET_ACCESS_KEY
    region = var.region
}

provider "cloudflare" {
    api_token = var.CLOUDFLARE_API_TOKEN
}

provider "acme" {
    server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

resource "aws_s3_bucket" "website-dev" {
    bucket = "jpolanskywebsite-dev"
    
    tags = {
        Name = "jpolanskywebsite-dev"
    }
}

data "aws_iam_policy_document" "bucket-policy" {
    statement {
        actions = ["s3:GetObject"]
        resources = ["${aws_s3_bucket.website-dev.arn}/*"]

        principals {
            type = "AWS"
            identifiers = [aws_cloudfront_origin_access_identity.oai.iam_arn]
        }
    }
}

resource "aws_s3_bucket_policy" "bucket-policy" {
    bucket = aws_s3_bucket.website-dev.id
    policy = data.aws_iam_policy_document.bucket-policy.json
}

resource "aws_s3_bucket_website_configuration" "website-config" {
    bucket = aws_s3_bucket.website-dev.id
    
    index_document {
        suffix = "index.html"
    }
}

resource "aws_acm_certificate" "cert" {
    domain_name = "aws.${var.DOMAIN_NAME}"
    validation_method = "DNS"
    tags = {
        Name = "jpolanskywebsite-dev"
    }
}

resource "aws_acm_certificate_validation" "cert-validation" {
    certificate_arn = aws_acm_certificate.cert.arn
    validation_record_fqdns = [for record in aws_acm_certificate.cert.domain_validation_options : record.resource_record_name]
    depends_on = [ cloudflare_record.cert-validation ]
}

resource "cloudflare_record" "cert-validation" {
    for_each = {
        for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
            name   = dvo.resource_record_name
            value = dvo.resource_record_value
            type   = dvo.resource_record_type
        }
    }    
    
    zone_id = var.CLOUDFLARE_ZONE_ID
    name = each.value.name
    value = each.value.value
    type = each.value.type
    proxied = false
}

resource "aws_cloudfront_origin_access_identity" "oai" {
    comment = "OAI for jpolanskywebsite-dev"
}

resource "aws_cloudfront_distribution" "website" {
    enabled = true
    is_ipv6_enabled = true
    default_root_object = "index.html"
    price_class = "PriceClass_100"
    aliases = ["aws.${var.DOMAIN_NAME}"]
    tags = {
        Name = "jpolanskywebsite-dev"
    }
    
    origin {
        domain_name = aws_s3_bucket.website-dev.bucket_regional_domain_name
        origin_id = aws_s3_bucket.website-dev.bucket_regional_domain_name

        s3_origin_config {
            origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
        }
    }
    
    default_cache_behavior {
        allowed_methods = ["GET", "HEAD", "OPTIONS"]
        cached_methods = ["GET", "HEAD", "OPTIONS"]
        target_origin_id = aws_s3_bucket.website-dev.bucket_regional_domain_name
        viewer_protocol_policy = "redirect-to-https"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
        
        forwarded_values {
            query_string = false
            
            cookies {
                forward = "none"
            }
        }
    }

    viewer_certificate {
        acm_certificate_arn = aws_acm_certificate_validation.cert-validation.certificate_arn
        ssl_support_method = "sni-only"
    }

    restrictions {
        
        geo_restriction {
            restriction_type = "none"
        }
    }
}

resource "cloudflare_record" "cname" {
    zone_id = var.CLOUDFLARE_ZONE_ID
    name = "aws.${var.DOMAIN_NAME}"
    value = aws_cloudfront_distribution.website.domain_name
    type = "CNAME"
    proxied = false
}

resource "aws_s3_object" "html" {
    for_each = fileset("web/", "*.html")
    bucket = aws_s3_bucket.website-dev.id
    key = each.value
    source = "web/${each.value}"
    content_type = "text/html"
    etag = filemd5("web/${each.value}")
    acl = "public-read"
}

resource "aws_s3_object" "css" {
    for_each = fileset("web/", "*.css")
    bucket = aws_s3_bucket.website-dev.id
    key = each.value
    source = "web/${each.value}"
    content_type = "text/css"
    etag = filemd5("web/${each.value}")
    acl = "public-read"
}

resource "aws_s3_object" "js" {
    for_each = fileset("web/", "*.js")
    bucket = aws_s3_bucket.website-dev.id
    key = each.value
    source = "web/${each.value}"
    content_type = "application/javascript"
    etag = filemd5("web/${each.value}")
    acl = "public-read"
}

resource "aws_dynamodb_table" "visitor_count_db" {
  name = "VisitorCount"
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Effect = "Allow"
        Sid = ""
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_access" {
  name = "lambda_dynamodb_access"
  description = "IAM policy for accessing DynamoDB from Lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
        ]
        Resource = aws_dynamodb_table.visitor_count_db.arn
        Effect = "Allow"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb_access_attachment" {
  role = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_access.arn
}

data "archive_file" "lambda_zip" {
  type = "zip"
  source_dir = "function"
  output_path = "zip/visitorcount.zip"
}

resource "aws_lambda_function" "visitor_counter" {
  function_name = "visitorCounter"
  handler = "index.lambda_handler"
  role = aws_iam_role.lambda_execution_role.arn
  runtime = "python3.8"
  filename = data.archive_file.lambda_zip.output_path
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)
}

resource "aws_api_gateway_rest_api" "visitor_count_api" {
  name = "VisitorCounterAPI"
  description = "API for handling visitor counts"
}

resource "aws_api_gateway_resource" "VisitorCounterResource" {
  rest_api_id = aws_api_gateway_rest_api.visitor_count_api.id
  parent_id = aws_api_gateway_rest_api.visitor_count_api.root_resource_id
  path_part = "visitorcount"
}

resource "aws_api_gateway_method" "cors_options" {
  rest_api_id   = aws_api_gateway_rest_api.visitor_count_api.id
  resource_id   = aws_api_gateway_resource.VisitorCounterResource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method_response" "cors_options_response_200" {
  rest_api_id = aws_api_gateway_rest_api.visitor_count_api.id
  resource_id = aws_api_gateway_resource.VisitorCounterResource.id
  http_method = aws_api_gateway_method.cors_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true,
  }
}

resource "aws_api_gateway_integration_response" "cors_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.visitor_count_api.id
  resource_id = aws_api_gateway_resource.VisitorCounterResource.id
  http_method = aws_api_gateway_method.cors_options.http_method
  status_code = aws_api_gateway_method_response.cors_options_response_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_deployment" "visitor_count_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.LambdaIntegration,
  ]

  rest_api_id = aws_api_gateway_rest_api.visitor_count_api.id
  stage_name = "prod"
}

output "api_endpoint" {
  value = "${aws_api_gateway_deployment.visitor_count_api_deployment.invoke_url}visitorcount"
}