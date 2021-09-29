from awsglue.utils import getResolvedOptions
from botocore.exceptions import ClientError
from datetime import datetime
from pysitemap import crawler
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError
from urllib.parse import urlparse
import boto3
import os
import sys

# Copy the token from Slack App and paste here.
ACCESS_TOKEN = "[BOT USER OAUTH TOKEN]"
SLACK_CHANNEL = "sitemap_generator"

# S3 Bucket which stores the generated XML sitemap file.
S3_BUCKET = "[S3 Bucket]"
AWS_REGION = "ap-northeast-1"


def post_message(msg):

    client = WebClient(token=ACCESS_TOKEN)

    if msg is not None:

        try:
            client.chat_postMessage(channel=SLACK_CHANNEL, text=msg)
        except SlackApiError as e:
            assert e.response["error"]

    return(None)


def process(root_url, event_user):

    out_file_name = "{}.sitemap.xml".format(urlparse(root_url).netloc)

    crawler_start = datetime.utcnow().timestamp()
    crawler(root_url, out_file=out_file_name)
    crawler_time = datetime.utcnow().timestamp() - crawler_start

    s3_client = boto3.client('s3')
    s3_key = "sitemap/{}".format(out_file_name)

    try:
        s3_client.upload_file(out_file_name, S3_BUCKET, s3_key)
        os.remove(out_file_name)
        post_msg = "<@{}> https://s3.{}.amazonaws.com/{}/{}\n Crawler time: {:.2f} seconds".format(event_user, AWS_REGION, S3_BUCKET, s3_key, crawler_time)
    except ClientError as e:
        post_msg = "Error uploading file"

    post_message(post_msg)

    return(post_msg)


if __name__ == "__main__":

    args = getResolvedOptions(sys.argv, ['JOB_NAME', 'root_url', 'event_user'])
    process(args['root_url'], args['event_user'])