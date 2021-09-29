## This repo ducuments AWS Lambda / Gule code implementation and Terraform deployment for the blog [The Serverless Age - Hands-on Introduction of Creating Slack App Interface to Access AWS Microservice](https://medium.com/p/ed9eb1133e02/edit).
---
### Steps of running the code:
- Create a Slack App with trigger events enabled as descriped in the blog part 3.
- Configure the Slack App Verification Token and Bot User OAuth Token in `sitemap_generator_lambda.py` and `sitemap_generator_glue.py` as descriped in the blog part 4.
- Set the AWS Lambda / Glue execution roles in `main.tf` according to your personalized AWS account.
- Run the following commands in the terminal.
    ```tf
    terraform init
    terraform apply
    ```
- Copy the output url to Slack App to connect the app with AWS Lambda function as descriped in the blog part 5.