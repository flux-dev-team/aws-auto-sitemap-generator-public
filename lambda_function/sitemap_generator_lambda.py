from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError
from urllib.parse import urlparse
import boto3
import json

# Copy the token from Slack App and paste here.
VERIFICATION_TOKEN = "[SLACK APP VERIFICATION TOKEN]"
ACCESS_TOKEN = "[BOT USER OAUTH TOKEN]"

SLACK_CHANNEL = "sitemap_generator"
GLUE_JOB_NAME = "sitemap-generator-tf"


def verify(data):

    if data['token'] == VERIFICATION_TOKEN:
        rep_body = data['challenge']
    else:
        rep_body = "verification failed"

    return({"challenge": rep_body})


def url_validator(url):

    try:
        result = urlparse(url)
        return(all([result.scheme, result.netloc]))
    except:
        return(False)


def post_message(msg):

    client = WebClient(token=ACCESS_TOKEN)

    if msg is not None:

        try:
            client.chat_postMessage(channel=SLACK_CHANNEL, text=msg)
        except SlackApiError as e:
            assert e.response["error"]

    return(None)


def check_to_process_url(data):

    root_url = None

    if 'client_msg_id' in data['event'].keys():

        url = data['event']['text'].strip("<>")

        if url_validator(url) is True:
            root_url = urlparse(url).scheme + "://" + urlparse(url).netloc
        else:
            post_message("Invalid URL")

    return(root_url)


def lambda_handler(event, context):

    data = json.loads(event['body'])

    if 'X-Slack-Retry-Num' not in event['headers'].keys():

        if data["type"] == "url_verification":
            rep_body = verify(data)

        elif data["type"] == "event_callback":

            root_url = check_to_process_url(data)
            rep_body = "Valid request"

            if root_url is not None:

                client = boto3.client('glue')
                client.start_job_run(JobName=GLUE_JOB_NAME,
                                     Arguments={"--root_url": root_url, "--event_user": data['event']['user']})
        else:
            rep_body = "Invalid request"
    else:
        rep_body = "Avoid retry"

    response = {
        "isBase64Encoded": False,
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(rep_body)
    }

    return(response)
