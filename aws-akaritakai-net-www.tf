/*
 * Creates and hosts the akaritakai.net website
 */

# We have to define these MIME types because they get corrupted into binary/octet-stream somehow?
locals {
  content_types = {
    ".css" : "text/css",
    ".html" : "text/html",
    ".ico" : "image/vnd.microsoft.icon",
    ".js" : "application/javascript",
    ".png" : "image/png",
    ".rss" : "application/rss+xml",
    ".txt" : "text/plain",
    ".webp" : "image/webp",
    ".xml" : "application/xml"
  }
}

/*
 * Create the main S3 bucket for the site
 */
resource "aws_s3_bucket" "www_akaritakai_net" {
  bucket = "www-akaritakai-net"
}

data "aws_iam_policy_document" "www_akaritakai_net_s3_website_public_read" {
  statement {
    sid    = "PublicReadGetObject"
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.www_akaritakai_net.bucket}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "www_akaritakai_net" {
  bucket = aws_s3_bucket.www_akaritakai_net.id
  policy = data.aws_iam_policy_document.www_akaritakai_net_s3_website_public_read.json
}

# Upload our statically built website (www.akaritakai.net) to the S3 bucket
resource "aws_s3_object" "www_akaritakai_net" {
  for_each     = fileset("build/www-akaritakai-net/", "**/*")
  bucket       = aws_s3_bucket.www_akaritakai_net.id
  key          = each.value
  source       = "build/www-akaritakai-net/${each.value}"
  content_type = lookup(local.content_types, regex("\\.[^.]+$", each.value), "application/octet-stream")
  etag         = filemd5("build/www-akaritakai-net/${each.value}")
}

# Upload the wordle-solver project to the S3 bucket
resource "aws_s3_object" "wordle-solver" {
  for_each     = fileset("build/wordle-solver/", "**/*")
  bucket       = aws_s3_bucket.www_akaritakai_net.id
  key          = "wordle/${each.value}"
  source       = "build/wordle-solver/${each.value}"
  content_type = lookup(local.content_types, regex("\\.[^.]+$", each.value), "application/octet-stream")
  etag         = filemd5("build/wordle-solver/${each.value}")
}

/*
 * Create the /tmp/ bucket for the site
 */
resource "aws_s3_bucket" "www_akaritakai_net_tmp" {
  bucket = "www-akaritakai-net-tmp"
}

resource "aws_s3_bucket_lifecycle_configuration" "www_akaritakai_net_tmp" {
  bucket = aws_s3_bucket.www_akaritakai_net_tmp.id
  rule {
    id = "delete-after-30-days"
    expiration {
      days = 30
    }
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "www_akaritakai_net_tmp_s3_website_public_read" {
  statement {
    sid    = "PublicReadGetObject"
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.www_akaritakai_net_tmp.bucket}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "www_akaritakai_net_tmp" {
  bucket = aws_s3_bucket.www_akaritakai_net_tmp.id
  policy = data.aws_iam_policy_document.www_akaritakai_net_tmp_s3_website_public_read.json
}

/*
 * Create the CloudFront distribution
 */

// Set up the Cloudfront certificate
resource "aws_acm_certificate" "www_akaritakai_net" {
  domain_name               = "akaritakai.net"
  subject_alternative_names = ["www.akaritakai.net"]
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
  validation_method = "DNS"
}

// Set up the DNS records to validate the certificate
resource "aws_route53_record" "cert_www_akaritakai_net" {
  for_each = {
    for dvo in aws_acm_certificate.www_akaritakai_net.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.akaritakai_net.zone_id
}

resource "aws_acm_certificate_validation" "www_akaritakai_net" {
  certificate_arn         = aws_acm_certificate.www_akaritakai_net.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_www_akaritakai_net : record.fqdn]
}

resource "aws_cloudfront_function" "redirect_root" {
  name    = "redirect-root"
  runtime = "cloudfront-js-1.0"
  code    = <<EOD
function handler(event) {
  var request = event.request;
  if (request.uri == '/wordle') {
    return {
      statusCode: 301,
      statusDescription: 'Moved Permanently',
      headers: {
        'location': {
          'value': 'https://akaritakai.net/wordle/'
        }
      }
    };
  } else if (request.uri.endsWith('/')) {
    request.uri += 'index.html';
  } else if (!request.uri.includes('.')) {
    request.uri += '/index.html';
  }
  return request;
}
EOD
}

resource "aws_cloudfront_distribution" "www_akaritakai_net" {
  aliases = ["akaritakai.net", "www.akaritakai.net"]
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id        = aws_cloudfront_cache_policy.default.id
    compress               = true
    target_origin_id       = "S3-www-akaritakai-net"
    viewer_protocol_policy = "redirect-to-https"
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirect_root.arn
    }
    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.hsts.arn
    }
  }
  ordered_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id        = aws_cloudfront_cache_policy.default.id
    compress               = true
    target_origin_id       = "S3-www-akaritakai-net-tmp"
    viewer_protocol_policy = "redirect-to-https"
    path_pattern           = "tmp/*"
    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.hsts.arn
    }
  }
  default_root_object = "index.html"
  enabled             = true
  http_version        = "http2"
  is_ipv6_enabled     = true
  origin {
    domain_name = aws_s3_bucket.www_akaritakai_net.bucket_domain_name
    origin_id   = "S3-www-akaritakai-net"
  }
  origin {
    domain_name = aws_s3_bucket.www_akaritakai_net_tmp.bucket_domain_name
    origin_id   = "S3-www-akaritakai-net-tmp"
  }
  price_class = "PriceClass_100"
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = aws_acm_certificate_validation.www_akaritakai_net.certificate_arn
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}

/*
 * Create DNS records for the CloudFront distribution
 */
resource "aws_route53_record" "a_akaritakai_net" {
  name    = "akaritakai.net"
  type    = "A"
  zone_id = aws_route53_zone.akaritakai_net.zone_id
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.www_akaritakai_net.domain_name
    zone_id                = aws_cloudfront_distribution.www_akaritakai_net.hosted_zone_id
  }
}

resource "aws_route53_record" "aaaa_akaritakai_net" {
  name    = "akaritakai.net"
  type    = "AAAA"
  zone_id = aws_route53_zone.akaritakai_net.zone_id
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.www_akaritakai_net.domain_name
    zone_id                = aws_cloudfront_distribution.www_akaritakai_net.hosted_zone_id
  }
}

resource "aws_route53_record" "caa_akaritakai_net" {
  name    = "akaritakai.net"
  type    = "CAA"
  zone_id = aws_route53_zone.akaritakai_net.zone_id
  ttl     = 300
  records = [
    "0 issue \"amazon.com\""
  ]
}

resource "aws_route53_record" "a_www_akaritakai_net" {
  name    = "www.akaritakai.net"
  type    = "A"
  zone_id = aws_route53_zone.akaritakai_net.zone_id
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.www_akaritakai_net.domain_name
    zone_id                = aws_cloudfront_distribution.www_akaritakai_net.hosted_zone_id
  }
}

resource "aws_route53_record" "aaaa_www_akaritakai_net" {
  name    = "www.akaritakai.net"
  type    = "AAAA"
  zone_id = aws_route53_zone.akaritakai_net.zone_id
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.www_akaritakai_net.domain_name
    zone_id                = aws_cloudfront_distribution.www_akaritakai_net.hosted_zone_id
  }
}

resource "aws_route53_record" "caa_www_akaritakai_net" {
  name    = "www.akaritakai.net"
  type    = "CAA"
  zone_id = aws_route53_zone.akaritakai_net.zone_id
  ttl     = 300
  records = [
    "0 issue \"amazon.com\""
  ]
}