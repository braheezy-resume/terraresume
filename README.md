# terraresume
This project creates the AWS infrastructure that hosts my [cloudy resume](https://github.com/braheezy-resume/cloudy-resume).

## Usage
- Review `terraform.tfvars` for values to customize the deployment.
- Run the `terraform` commands:

      terraform plan
      terraform apply
- As the resources come up, login to AWS
- Go to Route 53 and open the hosted zone that Terraform created
- Also in Route 53, open the Registered Domains area
- Update the domain to use the 4 name servers that were generated for the hosted zone
    - See [ACM DNS Validation Challenges](#ACM-DNS-Validation-Challenges) for why this is needed.

Eventually, a number of AWS services are stood up:
- **S3**: static website hosting for HTML version of resume
- **CloudFront**: CDN to serve the page quickly from edge locations
- **Route 53**: domain and route management
    - I bought the domain `braheezy.net` from Route 53
- **ACM**: SSL certificates for `braheezy.net` so traffic between Internet and CloudFront is HTTPS
- **DynamoDB**: NoSQL database to hold site metrics, like visitor count
- **Lambda**: Serverless hosting of [Go code I wrote](https://github.com/braheezy-resume/resume-analytics) to process site metrics
- **API Gateway**: Provide endpoint and handle requests to the Lambda function
- **CloudWatch**: Store logs from critical services

## ACM DNS Validation Challenges
To obtain a certificate for a custom domain, you need to provide proof you own the domain to the certificate provider. The automated way is the `DNS` validation method. Records are added to the domain that can be checked by external tools, thus verifying the owner. If your domain is in Route 53, AWS can add the records to the domain for you.

After applying the Terraform plan, the certificate validation could forever sit in *pending*" because the name servers assigned to my domain did not match the NS records that are generated when creating a hosted zone. Research shows Terraform is not equipped to fully handle DNS and name server management in AWS. I tried:
    - Hardcoding name servers in the NS and SOA records, letting ACM add only the CNAME record it needed. Domain was unreachable
    - Using what AWS calls Record Delegation Sets. Terraform didn't seem to support it. You need the aws cli directly.

So I am left with this one manual step of editing the DNS servers when this infrastructure is first rolled out.
