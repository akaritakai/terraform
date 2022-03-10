/*
 * Sets up DNS entries for akaritakai.net in AWS
 */
resource "aws_route53_zone" "akaritakai_net" {
  name = "akaritakai.net"
  lifecycle {
    prevent_destroy = true
  }
}

/*
 * Set up DNSSEC
 */
resource "aws_kms_key" "dnssec_akaritakai_net" {
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  policy                   = data.aws_iam_policy_document.dnssec_ksk.json
}

resource "aws_route53_key_signing_key" "akaritakai_net" {
  name                       = "ksk"
  hosted_zone_id             = aws_route53_zone.akaritakai_net.zone_id
  key_management_service_arn = aws_kms_key.dnssec_akaritakai_net.arn
}

resource "aws_route53_hosted_zone_dnssec" "akaritakai_net" {
  hosted_zone_id = aws_route53_key_signing_key.akaritakai_net.hosted_zone_id
}

/*
 * Set up records for Google Workspace Mail and Keybase
 */
resource "aws_route53_record" "mx_akaritakai_net" {
  name    = "akaritakai.net"
  type    = "MX"
  zone_id = aws_route53_zone.akaritakai_net.zone_id
  ttl     = 300
  records = [
    "1 aspmx.l.google.com.",
    "5 alt1.aspmx.l.google.com.",
    "5 alt2.aspmx.l.google.com.",
    "10 alt3.aspmx.l.google.com.",
    "10 alt4.aspmx.l.google.com."
  ]
}

resource "aws_route53_record" "txt_akaritakai_net" {
  name    = "akaritakai.net"
  type    = "TXT"
  zone_id = aws_route53_zone.akaritakai_net.zone_id
  ttl     = 300
  records = [
    "v=spf1 include:_spf.google.com ~all",
    "keybase-site-verification=3ZUGns24mLq2hS4sKIxuzk9Z7YQSQEDg0jR-5Hg05Tc"
  ]
}

resource "aws_route53_record" "dmarc_akaritakai_net" {
  name    = "_dmarc.akaritakai.net"
  type    = "TXT"
  zone_id = aws_route53_zone.akaritakai_net.zone_id
  ttl     = 300
  records = [
    "v=DMARC1; p=quarantine; rua=mailto:mailauth-reports@google.com"
  ]
}

resource "aws_route53_record" "dkim_akaritakai_net" {
  name    = "google._domainkey.akaritakai.net"
  type    = "TXT"
  zone_id = aws_route53_zone.akaritakai_net.zone_id
  ttl     = 300
  records = [
    "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCLuyKzddzeep4q8p1D2s8EFcnOTrLGPrI5JAbPz1LMxDQeqEEyiRzegwLaxfKubysQSs5NrvbN2O3yTBjB48inEObVV0eM20sVA1IIAdcHiOoDRlKIYRLpBff9SJ1k84l1hRHQVtygdkXt08JGy6agn06r10utpTA9otdi7Ky03QIDAQAB"
  ]
}