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
    zone_id = var.CLOUDFLARE_ZONE_ID
    name = aws_acm_certificate.cert.domain_validation_options[0].resource_record_name
    value = aws_acm_certificate.cert.domain_validation_options[0].resource_record_value
    type = "TXT"
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
    }

    s3_origin_config {
        origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
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

