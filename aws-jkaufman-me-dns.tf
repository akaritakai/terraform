/*
 * Sets up DNS entries for jkaufman.me in AWS
 */
resource "aws_route53_zone" "jkaufman_me" {
  name = "jkaufman.me"
  lifecycle {
    prevent_destroy = true
  }
}

/*
 * Set up DNSSEC
 */
resource "aws_kms_key" "dnssec_jkaufman_me" {
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  policy                   = data.aws_iam_policy_document.dnssec_ksk.json
}

resource "aws_route53_key_signing_key" "jkaufman_me" {
  name                       = "ksk"
  hosted_zone_id             = aws_route53_zone.jkaufman_me.zone_id
  key_management_service_arn = aws_kms_key.dnssec_jkaufman_me.arn
}

resource "aws_route53_hosted_zone_dnssec" "jkaufman_me" {
  hosted_zone_id = aws_route53_key_signing_key.jkaufman_me.hosted_zone_id
}

/*
 * Set up records for Google Workspace Mail and Keybase
 */
resource "aws_route53_record" "mx_jkaufman_me" {
  name    = "jkaufman.me"
  type    = "MX"
  zone_id = aws_route53_zone.jkaufman_me.zone_id
  ttl     = 300
  records = [
    "1 aspmx.l.google.com.",
    "5 alt1.aspmx.l.google.com.",
    "5 alt2.aspmx.l.google.com.",
    "10 alt3.aspmx.l.google.com.",
    "10 alt4.aspmx.l.google.com."
  ]
}

resource "aws_route53_record" "txt_jkaufman_me" {
  name    = "jkaufman.me"
  type    = "TXT"
  zone_id = aws_route53_zone.jkaufman_me.zone_id
  ttl     = 300
  records = [
    "v=spf1 include:_spf.google.com ~all",
    "keybase-site-verification=ygMqq9mWRqwr-Tdvo7hO9niOAOO-_fPr-mEgcAqfgR4"
  ]
}

resource "aws_route53_record" "dmarc_jkaufman_me" {
  name    = "_dmarc.jkaufman.me"
  type    = "TXT"
  zone_id = aws_route53_zone.jkaufman_me.zone_id
  ttl     = 300
  records = [
    "v=DMARC1; p=quarantine; rua=mailto:mailauth-reports@google.com"
  ]
}

resource "aws_route53_record" "dkim_jkaufman_me" {
  name    = "google._domainkey.jkaufman.me"
  type    = "TXT"
  zone_id = aws_route53_zone.jkaufman_me.zone_id
  ttl     = 300
  records = [
    "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCSMIdDG0WXAUu1ZjhFe1sJMqXOiXHVujOOI5s84ee7RvsMwj+nZORS08+9H+MRyHaJ4LuyEs4dLBnjK4mJ2ilRKeVBNFakSjVka1AuW9/wMis1NbeH5LhWxskYAaIUEGWR6rFbgmgpI6qW+FaMOOGI785PiXkPRLRusF+drDLkTQIDAQAB"
  ]
}