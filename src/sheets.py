"""
Google Sheets integration module.
Handles appending rows to a Google Spreadsheet using Service Account credentials.

This implementation reads the spreadsheet metadata to discover the first sheet's
title and builds a safe range like `'Sheet Name'!A:D`. This avoids errors when the
sheet is not named "Sheet1" or contains spaces/special characters.
"""

from google.oauth2 import service_account
from googleapiclient.discovery import build
import logging
import os

SCOPES = ["https://www.googleapis.com/auth/spreadsheets"]
CREDENTIALS_PATH = os.getenv("CREDENTIALS_PATH", "config/credentials.json")

logger = logging.getLogger(__name__)


def _get_first_sheet_title(service, spreadsheet_id):
    try:
        meta = service.get(spreadsheetId=spreadsheet_id).execute()
        sheets = meta.get("sheets", [])
        if sheets:
            return sheets[0].get("properties", {}).get("title", "Sheet1")
    except Exception:
        logger.exception("Failed to fetch spreadsheet metadata")
    return "Sheet1"


def append_row(spreadsheet_id, row):
    """
    Append a single row to the first sheet of the Google Spreadsheet.

    Args:
        spreadsheet_id (str): The ID of the Google Spreadsheet
        row (list): List of values to append [username, chat_id, text, timestamp]
    Returns:
        dict: The API response from the append call
    """
    creds = service_account.Credentials.from_service_account_file(
        CREDENTIALS_PATH,
        scopes=SCOPES,
    )

    service = build("sheets", "v4", credentials=creds).spreadsheets()

    # Discover first sheet title and build a safe range
    first_title = _get_first_sheet_title(service, spreadsheet_id)
    range_name = f"'{first_title}'!A:D"

    body = {"values": [row]}
    try:
        result = service.values().append(
            spreadsheetId=spreadsheet_id,
            range=range_name,
            valueInputOption="RAW",
            body=body,
        ).execute()
        logger.info("Appended row to %s: %s", range_name, row)
        return result
    except Exception:
        logger.exception("Failed to append row to Google Sheets")
        raise
