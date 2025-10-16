import argparse
import datetime
import os
import sys
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

# Full Gmail access allows read + permanent delete
SCOPES = ["https://mail.google.com/"]

def authenticate_gmail(credfile):
    """Authenticate and return Gmail service object"""
    creds = None
    token_path = os.path.splitext(credfile)[0] + "_token.json"

    # Load saved credentials if present
    if os.path.exists(token_path):
        creds = Credentials.from_authorized_user_file(token_path, SCOPES)

    # If credentials are missing or invalid, run OAuth flow
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists(credfile):
                print(f"❌ Error: credentials file not found at '{credfile}'")
                sys.exit(1)

            flow = InstalledAppFlow.from_client_secrets_file(credfile, SCOPES)
            creds = flow.run_local_server(port=0)

        # Save refreshed or new token next to credentials
        with open(token_path, "w") as token:
            token.write(creds.to_json())

    return build("gmail", "v1", credentials=creds)


def delete_messages_for_month(service, year, month):
    """Delete all messages from a specific month"""
    start_date = datetime.date(year, month, 1)
    if month == 12:
        end_date = datetime.date(year + 1, 1, 1) - datetime.timedelta(days=1)
    else:
        end_date = datetime.date(year, month + 1, 1) - datetime.timedelta(days=1)

    start_str = start_date.strftime("%Y/%m/%d")
    end_str = (end_date + datetime.timedelta(days=1)).strftime("%Y/%m/%d")  # exclusive end
    query = f"after:{start_str} before:{end_str}"

    print(f"🔍 Searching for messages from {start_str} to {end_str}...")

    results = service.users().messages().list(userId="me", q=query, maxResults=10000).execute()
    messages = results.get("messages", [])

    if not messages:
        print("No messages found for the specified month.")
        return

    print(f"Found {len(messages)} messages to delete.")
    batch_size = 999

    for i in range(0, len(messages), batch_size):
        batch = messages[i : i + batch_size]
        ids = [msg["id"] for msg in batch]
        print(f"🗑️  Deleting batch of {len(ids)} messages...")
        service.users().messages().batchDelete(userId="me", body={"ids": ids}).execute()

    print(f"✅ Successfully deleted {len(messages)} messages from {year}-{month:02d}")


def main():
    parser = argparse.ArgumentParser(description="Delete Gmail messages for a specific month")
    parser.add_argument("-y", "--year", type=int, required=True, help="Year (e.g., 2024)")
    parser.add_argument("-m", "--month", type=int, required=True, help="Month (1–12)")
    parser.add_argument(
        "-c",
        "--credfile",
        type=str,
        required=True,
        help="Full path to OAuth credentials JSON file (downloaded from Google Cloud Console)",
    )

    args = parser.parse_args()

    if not (1 <= args.month <= 12):
        print("❌ Error: Month must be between 1 and 12.")
        sys.exit(1)

    service = authenticate_gmail(args.credfile)

    print(f"⚠️  WARNING: This will permanently delete ALL messages from {args.year}-{args.month:02d}")
    confirm = input("Are you sure you want to continue? (yes/no): ")

    if confirm.lower() != "yes":
        print("Operation cancelled.")
        return

    delete_messages_for_month(service, args.year, args.month)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nOperation cancelled by user.")
        sys.exit(0)