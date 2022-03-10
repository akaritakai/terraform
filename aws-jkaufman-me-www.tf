/*
 * Creates and hosts the akaritakai.net website
 */

/*
 * Create the main S3 bucket for the site
 */
resource "aws_s3_bucket" "www_jkaufman_me" {
  bucket = "www-jkaufman-me"
}

data "aws_iam_policy_document" "www_jkaufman_me_s3_website_public_read" {
  statement {
    sid    = "PublicReadGetObject"
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::${aws_s3_bucket.www_jkaufman_me.bucket}/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "www_jkaufman_me" {
  bucket = aws_s3_bucket.www_jkaufman_me.id
  policy = data.aws_iam_policy_document.www_jkaufman_me_s3_website_public_read.json
}

# Upload the keybase.txt file to the S3 bucket
resource "aws_s3_object" "keybase_www_jkaufman_me" {
  bucket       = aws_s3_bucket.www_jkaufman_me.id
  key          = "keybase.txt"
  source       = "www.jkaufman.me/keybase.txt"
  content_type = "text/plain"
  etag         = filemd5("www.jkaufman.me/keybase.txt")
}

/*
 * Create the CloudFront distribution
 */

// Set up the Cloudfront certificate
resource "aws_acm_certificate" "www_jkaufman_me" {
  domain_name               = "jkaufman.me"
  subject_alternative_names = ["www.jkaufman.me"]
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
  validation_method = "DNS"
}

// Set up the DNS records to validate the certificate
resource "aws_route53_record" "cert_www_jkaufman_me" {
  for_each = {
    for dvo in aws_acm_certificate.www_jkaufman_me.domain_validation_options : dvo.domain_name => {
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
  zone_id         = aws_route53_zone.jkaufman_me.zone_id
}

resource "aws_acm_certificate_validation" "www_jkaufman_me" {
  certificate_arn         = aws_acm_certificate.www_jkaufman_me.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_www_jkaufman_me : record.fqdn]
}

// Create a lambda to redirect requests to akaritakai.net
resource "aws_cloudfront_function" "redirect_www_akaritakai_net" {
  name    = "redirect-www-akaritakai-net"
  runtime = "cloudfront-js-1.0"
  code    = <<EOD
function handler(event) {
  return {
    statusCode: 301,
    statusDescription: 'Moved Permanently',
    headers: {
      'location': {
        'value': 'https://akaritakai.net' + event.request.uri
      }
    }
  }
}
EOD
}

resource "aws_cloudfront_distribution" "www_jkaufman_me" {
  aliases = ["jkaufman.me", "www.jkaufman.me"]
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id        = aws_cloudfront_cache_policy.default.id
    compress               = true
    target_origin_id       = "S3-www-jkaufman-me"
    viewer_protocol_policy = "redirect-to-https"
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirect_www_akaritakai_net.arn
    }
    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.default_headers.arn
    }
  }
  ordered_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id        = aws_cloudfront_cache_policy.default.id
    compress               = true
    target_origin_id       = "S3-www-jkaufman-me"
    viewer_protocol_policy = "redirect-to-https"
    path_pattern           = "keybase.txt"
    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.default_headers.arn
    }
  }
  default_root_object = "index.html"
  enabled             = true
  http_version        = "http2"
  is_ipv6_enabled     = true
  origin {
    domain_name = aws_s3_bucket.www_jkaufman_me.bucket_domain_name
    origin_id   = "S3-www-jkaufman-me"
  }
  price_class = "PriceClass_100"
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn            = aws_acm_certificate_validation.www_jkaufman_me.certificate_arn
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }
}

/*
 * Create DNS records for the CloudFront distribution
 */
resource "aws_route53_record" "a_jkaufman_me" {
  name    = "jkaufman.me"
  type    = "A"
  zone_id = aws_route53_zone.jkaufman_me.zone_id
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.www_jkaufman_me.domain_name
    zone_id                = aws_cloudfront_distribution.www_jkaufman_me.hosted_zone_id
  }
}

resource "aws_route53_record" "aaaa_jkaufman_me" {
  name    = "jkaufman.me"
  type    = "AAAA"
  zone_id = aws_route53_zone.jkaufman_me.zone_id
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.www_jkaufman_me.domain_name
    zone_id                = aws_cloudfront_distribution.www_jkaufman_me.hosted_zone_id
  }
}

resource "aws_route53_record" "caa_jkaufman_me" {
  name    = "jkaufman.me"
  type    = "CAA"
  zone_id = aws_route53_zone.jkaufman_me.zone_id
  ttl     = 300
  records = [
    "0 issue \"amazon.com\""
  ]
}

resource "aws_route53_record" "a_www_jkaufman_me" {
  name    = "www.jkaufman.me"
  type    = "A"
  zone_id = aws_route53_zone.jkaufman_me.zone_id
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.www_jkaufman_me.domain_name
    zone_id                = aws_cloudfront_distribution.www_jkaufman_me.hosted_zone_id
  }
}

resource "aws_route53_record" "aaaa_www_jkaufman_me" {
  name    = "www.jkaufman.me"
  type    = "AAAA"
  zone_id = aws_route53_zone.jkaufman_me.zone_id
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.www_jkaufman_me.domain_name
    zone_id                = aws_cloudfront_distribution.www_jkaufman_me.hosted_zone_id
  }
}

resource "aws_route53_record" "caa_www_jkaufman_me" {
  name    = "www.jkaufman.me"
  type    = "CAA"
  zone_id = aws_route53_zone.jkaufman_me.zone_id
  ttl     = 300
  records = [
    "0 issue \"amazon.com\""
  ]
}