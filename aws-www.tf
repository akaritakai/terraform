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
resource "aws_cloudfront_function" "default_headers" {
  name    = "default-headers"
  runtime = "cloudfront-js-1.0"
  code    = <<EOD
function handler(event) {
  var response = event.response;
  var headers = response.headers;
  // Add HSTS headers to the response.
  headers['strict-transport-security'] = {
    value: 'max-age=63072000; includeSubDomains; preload'
  };
  // Add cache headers to cache the data for at least 1 day, or 30 days if tmp or static hosting.
  if (event.request.uri.startsWith('/tmp/') || event.request.uri.startsWith('/static/')) {
    headers['cache-control'] = {
      value: 'max-age=2592000, private, immutable'
    };
  } else {
    headers['cache-control'] = {
      value: 'max-age=86400, public'
    };
  }
  // Add a restrictive CSP for the site and a more generous one for the blog
  if (event.request.uri.startsWith('/blog/')) {
      var policies = [
          "base-uri 'self';",
          "connect-src 'self';",
          "default-src 'none';",
          "font-src 'self';",
          "form-action 'self';",
          "frame-ancestors 'none';",
          "frame-src 'self' https://www.youtube-nocookie.com https://platform.twitter.com;",
          "img-src 'self' https://i.ytimg.com https://syndication.twitter.com;",
          "manifest-src 'self';",
          "media-src 'self';",
          "object-src 'none';",
          "script-src 'self' https://platform.twitter.com;",
          "style-src 'self' https://platform.twitter.com;",
          "worker-src 'none';"
      ];
      headers['content-security-policy'] = {
          value: policies.join(' ')
      }
  } else {
      var policies = [
          "base-uri 'self';",
          "connect-src 'self';",
          "default-src 'none';",
          "font-src 'self';",
          "form-action 'self';",
          "frame-ancestors 'none';",
          "frame-src 'self';",
          "img-src 'self';",
          "manifest-src 'self';",
          "media-src 'self';",
          "object-src 'none';",
          "script-src 'self';",
          "style-src 'self';",
          "worker-src 'none';"
      ];
      headers['content-security-policy'] = {
          value: policies.join(' ')
      }
  }
  // Add various security headers
  headers['x-content-type-options'] = {
    value: 'nosniff'
  };
  headers['x-frame-options'] = {
    value: 'DENY'
  };
  headers['x-xss-protection'] = {
    value: '1; mode=block'
  };
  headers['referrer-policy'] = {
    value: 'no-referrer'
  };
  return response;
}
EOD
}
