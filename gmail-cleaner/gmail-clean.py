import argparse
import datetime
import os
import sys
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

SCOPES = ["https://mail.google.com/"]

def authenticate_gmail(credfile):
    creds = None
    token_path = credfile + ".token.json"

    if os.path.exists(token_path):
        creds = Credentials.from_authorized_user_file(token_path, SCOPES)

    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            if not os.path.exists(credfile):
                print(f"❌ Error: credentials file not found at '{credfile}'")
                sys.exit(1)
            flow = InstalledAppFlow.from_client_secrets_file(credfile, SCOPES)
            creds = flow.run_local_server(port=0)

        with open(token_path, "w") as token:
            token.write(creds.to_json())

    return build("gmail", "v1", credentials=creds)


def delete_messages_for_month(service, year, month, location, sender):
    start_date = datetime.date(year, month, 1)
    if month == 12:
        end_date = datetime.date(year + 1, 1, 1) - datetime.timedelta(days=1)
    else:
        end_date = datetime.date(year, month + 1, 1) - datetime.timedelta(days=1)

    start_str = start_date.strftime("%Y/%m/%d")
    end_str = (end_date + datetime.timedelta(days=1)).strftime("%Y/%m/%d")  # exclusive end
    
    # Build query with location (label)
    query_parts = [f"after:{start_str}", f"before:{end_str}"]
    
    if location.lower() == "inbox":
        query_parts.append("in:inbox")
    else:
        query_parts.append(f"label:{location}")
    
    # Add sender filter if provided
    if sender:
        query_parts.append(f"from:{sender}")
    
    query = " ".join(query_parts)
    
    location_display = "inbox" if location.lower() == "inbox" else f"label '{location}'"
    sender_display = f" from sender '{sender}'" if sender else ""
    
    print(f"🔍 Searching for messages in {location_display}{sender_display} from {start_str} to {end_str}...")

    results = service.users().messages().list(userId="me", q=query, maxResults=10000).execute()
    messages = results.get("messages", [])

    if not messages:
        print(f"No messages found in {location_display}{sender_display} for the specified month.")
        return

    print(f"Found {len(messages)} messages to delete from {location_display}{sender_display}.")
    batch_size = 999

    for i in range(0, len(messages), batch_size):
        batch = messages[i : i + batch_size]
        ids = [msg["id"] for msg in batch]
        print(f"🗑️  Deleting batch of {len(ids)} messages from {location_display}{sender_display}...")
        service.users().messages().batchDelete(userId="me", body={"ids": ids}).execute()

    print(f"✅ Successfully deleted {len(messages)} messages from {location_display}{sender_display} ({year}-{month:02d})")


def delete_messages_for_year(service, year, location, sender):
    """Delete all messages from the entire year for a specific location and optional sender"""
    for month in range(1, 13):
        delete_messages_for_month(service, year, month, location, sender)


def main():
    parser = argparse.ArgumentParser(
        description="Delete Gmail messages for a specific month or entire year from a location (inbox or label) with optional sender filter"
    )
    parser.add_argument("-y", "--year", type=int, required=True, help="Year (e.g., 2024)")
    parser.add_argument("-m", "--month", type=int, choices=range(1, 13), help="Month (1–12). Omit to delete entire year")
    parser.add_argument(
        "-c", "--credfile", type=str, required=True, help="Full path to OAuth credentials JSON file"
    )
    parser.add_argument(
        "-l", "--location", type=str, required=True, 
        help="Location to delete from: 'inbox' (case-insensitive) for inbox, or any other Gmail label/tag name"
    )
    parser.add_argument(
        "-s", "--sender", type=str, 
        help="Optional: Filter by sender email address (e.g., 'newsletter@example.com')"
    )
    parser.add_argument(
        "-f", "--force", action="store_true", help="Skip confirmation prompt (ignored if deleting entire year)"
    )

    args = parser.parse_args()

    service = authenticate_gmail(args.credfile)
    
    location_display = "inbox" if args.location.lower() == "inbox" else f"label '{args.location}'"
    sender_display = f" from sender '{args.sender}'" if args.sender else ""
    
    if args.month is None:
        # Deleting entire year
        print(f"⚠️  WARNING: This will permanently delete ALL messages from {args.year} (entire year) in {location_display}{sender_display}.")
        confirm = input("Are you sure you want to continue? (yes/no): ")
        if confirm.lower() != "yes":
            print("Operation cancelled.")
            return
        delete_messages_for_year(service, args.year, args.location, args.sender)
    else:
        # Deleting specific month
        if not args.force:
            print(f"⚠️  WARNING: This will permanently delete ALL messages from {args.year}-{args.month:02d} in {location_display}{sender_display}.")
            confirm = input("Are you sure you want to continue? (yes/no): ")
            if confirm.lower() != "yes":
                print("Operation cancelled.")
                return
        else:
            print(f"⚠️  WARNING: Skipping confirmation. Deleting ALL messages from {args.year}-{args.month:02d} in {location_display}{sender_display}.")

        delete_messages_for_month(service, args.year, args.month, args.location, args.sender)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nOperation cancelled by user.")
        sys.exit(0)
