variable "region" {
    type = string
    default = "us-east-1"
}

variable "DOMAIN_NAME" {
    type = string
    default = "jon-polansky.com"
}

variable "AWS_ACCESS_KEY_ID" {
    type = string
}

variable "AWS_SECRET_ACCESS_KEY" {
    type = string
}

variable "AWS_SESSION_TOKEN" {
    type = string
}

variable "CLOUDFLARE_API_TOKEN" {
    type = string
}

variable "CLOUDFLARE_ZONE_ID" {
    type = string
}

variable "EMAIL_ADDRESS" {
    type = string
}