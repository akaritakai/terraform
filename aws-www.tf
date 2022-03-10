/*
 * A CloudFront policy that supports compression and a 1-day cache.
 */
resource "aws_cloudfront_cache_policy" "default" {
  name        = "default-cache-policy"
  min_ttl     = 86400
  default_ttl = 86400
  max_ttl     = 86400
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

/*
 * Return an HSTS header in a response.
 */
resource "aws_cloudfront_function" "hsts" {
  name    = "hsts"
  runtime = "cloudfront-js-1.0"
  code    = <<EOD
function handler(event) {
  var response = event.response;
  var headers = response.headers;
  headers['strict-transport-security'] = {
    value: 'max-age=63072000; preload'
  };
  return response;
}
EOD
}