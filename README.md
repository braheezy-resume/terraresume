This project creates the AWS infrastructure that hosts my [resume](https://github.com/braheezy-resume/resume).

- S3 bucket stores the HTML version of my resume. The bucket is configure as a public-read static website
- CloudFront to be a CDN and serve the page quickly from edge locations
- Route 53 for domain and route management
    - I bought the domain `braheezy.net` from Route 53
- ACM certificate for `braheezy.net` to provide HTTPS coverage between viewer and CloudFront

## ACM DNS Validation Challenges
To obtain a certificate for a custom domain, you need to provide to the certificate provider proof you own the domain. The automated way is the `DNS` validation method. Records are added to the domain that can be checked by external tools, thus verifying the owner. If your domain is in Route 53, AWS can add the records to the domain for you.

I would manually step through certificate creation in ACM and have it put the records in my domain. But the validation would forever sit in "pending". After many hours of headbanging, the culprit was the name servers assigned to my domain did not match the NS records that are generated when creating a hosted zone. Research shows Terraform is not equipped to fully handle DNS and name server management in AWS. I tried:
    - Hardcoding name servers in the NS and SOA records, letting ACM add only the CNAME record it needed. Domain was unreachable
    - Using what AWS calls Record Delegation Sets. Terraform didn't seem to support it. You need the aws cli directly.

## Usage
- Make sure the content in `terraform.tfvars` is correct
- Run the `terraform` commands:

    terraform plan
    terraform apply
- As the resources come up, login to AWS
- Go to Route 53 and open the hosted zone that Terraform created
- Also in Route 53, open the Registered Domains area.
- Update the domain to use the 4 name servers that were generated for the hosted zone