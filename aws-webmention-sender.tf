/*
 * Creates a periodic lambda that runs the webmention sender daily.
 */

/*
 * Create the S3 bucket that holds our database.
 */
resource "aws_s3_bucket" "webmention_db" {
  bucket = "akaritakai-webmention-sender-db"
}

resource "aws_s3_bucket_acl" "webmention_db" {
  bucket = aws_s3_bucket.webmention_db.id
  acl    = "private"
}

/*
 * Create the lambda function.
 */
module "python_archive" {
  source               = "rojopolis/lambda-python-archive/aws"
  version              = "0.1.6"
  src_dir              = "${path.module}/webmention-sender/"
  output_path          = "${path.module}/webmention-sender-lambda.zip"
  install_dependencies = true
}

data "aws_iam_policy_document" "webmention_sender_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "webmention_sender" {
  name               = "webmention-sender-role"
  assume_role_policy = data.aws_iam_policy_document.webmention_sender_role.json
}

data "aws_iam_policy_document" "webmention_sender_role_policy" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PubObject", "s3:PutObjectVersion"]
    resources = ["arn:aws:s3:::${aws_s3_bucket.webmention_db.bucket}/webmention.json"]
  }
}

resource "aws_iam_role_policy" "webmention_sender" {
  name   = "webmention-sender-role-policy"
  role   = aws_iam_role.webmention_sender.id
  policy = data.aws_iam_policy_document.webmention_sender_role_policy.json
}

resource "aws_lambda_function" "webmention_sender" {
  function_name    = "webmention-sender"
  filename         = module.python_archive.archive_path
  handler          = "main.lambda_handler"
  source_code_hash = module.python_archive.source_code_hash
  role             = aws_iam_role.webmention_sender.arn
  runtime          = "python3.9"
  timeout          = 900
}

/*
 * Create the lambda schedule.
 */
resource "aws_cloudwatch_event_rule" "webmention_sender" {
  name                = "webmention-sender-rule"
  schedule_expression = "rate(1 day)"
}

resource "aws_cloudwatch_event_target" "webmention_sender" {
  rule      = aws_cloudwatch_event_rule.webmention_sender.name
  target_id = "webmention-sender-target"
  arn       = aws_lambda_function.webmention_sender.arn
}

resource "aws_lambda_permission" "allow_event_target" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webmention_sender.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.webmention_sender.arn
}