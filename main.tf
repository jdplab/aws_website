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
    }
}

provider "aws" {
    access_key = var.AWS_ACCESS_KEY_ID
    secret_key = var.AWS_SECRET_ACCESS_KEY
    token = var.AWS_SESSION_TOKEN
    region = var.region
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