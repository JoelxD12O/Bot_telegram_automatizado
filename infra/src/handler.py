"""
Lambda handler for Telegram webhook.
Receives Telegram messages and saves them to Google Sheets.
"""

import json
import os
from datetime import datetime
from .sheets import append_row

SPREADSHEET_ID = os.environ["SPREADSHEET_ID"]


def main(event, context):
    """
    Main Lambda handler function.
    
    Args:
        event: API Gateway event containing the Telegram webhook payload
        context: Lambda context object
        
    Returns:
        dict: HTTP response with status code 200
    """
    try:
        body = json.loads(event["body"])
        msg = body.get("message", {})

        # Extract message data
        text = msg.get("text", "")
        username = msg.get("from", {}).get("username", "unknown")
        chat_id = msg.get("chat", {}).get("id", "")
        timestamp = datetime.utcnow().isoformat()

        # Only process messages with text
        if text:
            append_row(
                SPREADSHEET_ID,
                [username, str(chat_id), text, timestamp]
            )

        return {
            "statusCode": 200,
            "body": json.dumps({"ok": True})
        }
    
    except Exception as e:
        print(f"Error processing message: {str(e)}")
        return {
            "statusCode": 200,  # Return 200 to avoid Telegram retries
            "body": json.dumps({"ok": False, "error": str(e)})
        }
