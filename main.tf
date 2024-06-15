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
    token = var.AWS_SESSION_TOKEN
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

resource "aws_s3_bucket_acl" "bucket-acl" {
    bucket = aws_s3_bucket.website-dev.id
    acl = "public-read"
}

resource "aws_s3_bucket_public_access_block" "bucket-public-access-block" {
    bucket = aws_s3_bucket.website-dev.id
    block_public_acls = false
    block_public_policy = false
    ignore_public_acls = false
    restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "bucket-policy" {
    bucket = aws_s3_bucket.website-dev.id
    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
            {
                Effect = "Allow",
                Principal = "*",
                Action = "s3:GetObject",
                Resource = "${aws_s3_bucket.website-dev.arn}/*"
            }
        ]
    })
}

resource "aws_s3_bucket_website_configuration" "website-config" {
    bucket = aws_s3_bucket.website-dev.id
    
    index_document {
        suffix = "index.html"
    }
}

resource "tls_private_key" "private_key" {
    algorithm = "RSA"
}

resource "acme_registration" "me" {
    account_key_pem = tls_private_key.private_key.private_key_pem
    email_address = var.EMAIL_ADDRESS
}

resource "acme_certificate" "cert" {
    account_key_pem = acme_registration.me.account_key_pem
    common_name = "aws.${var.DOMAIN_NAME}"
    key_type = "2048"

    dns_challenge {
        provider = "cloudflare"
        config = {
            CF_ZONE_API_TOKEN = var.CLOUDFLARE_API_TOKEN
            CF_DNS_API_TOKEN = var.CLOUDFLARE_API_TOKEN
            CLOUDFLARE_HTTP_TIMEOUT = "300"
        }
    }
}

resource "aws_acm_certificate" "cert" {
    private_key = acme_certificate.cert.private_key_pem
    certificate_body = acme_certificate.cert.certificate_pem
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
        acm_certificate_arn = aws_acm_certificate.cert.arn
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

