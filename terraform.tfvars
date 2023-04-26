# The main region the resources will be created in
aws_region = "us-west-1"
# The tag to apply to all resources
tag_name = "resume"
# The domain to use.
# Assumed to be created in Route 53 already
domain = "braheezy.net"
# The display name of the resume website!
resume_website = "resume.${var.domain}"
# The name of your resume HTML file
resume_html_file = "resume.html"
# Where the latest resume can be downloaded from
resume_html_file_url = "https://github.com/braheezy-resume/resume/releases/latest/download/resume.html"
# The name of the DynamoDB to store website metrics data
db_table_name = "site-analytics"
# DynamnoDB requires a partition key
db_partition_key = "metrics"
# The main thing we set up DynamoDB for is to record visitor count information. This is the name
# of that atrribute in the table.
db_count_attribute_name = "visitorCount"
# The name of the program that Lambda should call
lambda_handler_name = "count"
# How long to hold on to CloudWatch logs
cloudwatch_retention_days = 7
