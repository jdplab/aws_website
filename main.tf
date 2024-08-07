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

resource "aws_apigatewayv2_api" "visitorcount_http_api" {
  name          = "visitorcount_http_api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "visitorcount_lambda_integration" {
  api_id           = aws_apigatewayv2_api.visitorcount_http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.visitor_counter.invoke_arn
}

resource "aws_apigatewayv2_route" "visitorcount_route" {
  api_id    = aws_apigatewayv2_api.visitorcount_http_api.id
  route_key = "POST /visitorcount"
  target    = "integrations/${aws_apigatewayv2_integration.visitorcount_lambda_integration.id}"
}

resource "aws_apigatewayv2_deployment" "visitorcount_deployment" {
  api_id      = aws_apigatewayv2_api.visitorcount_http_api.id
  description = "Deployment for the VisitorCount API"

  triggers = {
    redeployment = sha256(jsonencode(aws_apigatewayv2_api.visitorcount_http_api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_apigatewayv2_stage" "visitorcount_stage" {
  api_id      = aws_apigatewayv2_api.visitorcount_http_api.id
  name        = "prod"
  auto_deploy = false
  deployment_id = aws_apigatewayv2_deployment.visitorcount_deployment.id
}

resource "aws_lambda_permission" "http_api_lambda" {
  statement_id  = "AllowExecutionFromHTTPAPI"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.visitorcount_http_api.execution_arn}/*/*"
}

resource "aws_apigatewayv2_cors_configuration" "visitorcount_cors" {
  api_id = aws_apigatewayv2_api.visitorcount_http_api.id

  allow_origins = ["https://aws.jon-polansky.com"]
  allow_methods = ["POST"]
  allow_headers = ["Content-Type"]
}

output "http_api_endpoint" {
  value = aws_apigatewayv2_api.visitorcount_http_api.api_endpoint
}