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


def delete_messages_by_filters(service, year, month, location, sender):
    # Build query based on filters
    query_parts = []

    # Add time filters if provided
    if year and month:
        start_date = datetime.date(year, month, 1)
        if month == 12:
            end_date = datetime.date(year + 1, 1, 1) - datetime.timedelta(days=1)
        else:
            end_date = datetime.date(year, month + 1, 1) - datetime.timedelta(days=1)
        start_str = start_date.strftime("%Y/%m/%d")
        end_str = (end_date + datetime.timedelta(days=1)).strftime("%Y/%m/%d")
        query_parts.extend([f"after:{start_str}", f"before:{end_str}"])
    elif year:
        start_str = f"{year}/01/01"
        end_str = f"{year + 1}/01/01"
        query_parts.extend([f"after:{start_str}", f"before:{end_str}"])

    # Add location filter
    if location.lower() == "inbox":
        query_parts.append("in:inbox")
    else:
        query_parts.append(f"label:{location}")

    # Add sender filter if provided
    if sender:
        query_parts.append(f"from:{sender}")

    query = " ".join(query_parts)

    # Build display strings
    location_display = "inbox" if location.lower() == "inbox" else f"label '{location}'"
    sender_display = f" from sender '{sender}'" if sender else ""

    if year and month:
        time_display = f"{year}-{month:02d}"
    elif year:
        time_display = f"year {year}"
    else:
        time_display = "ALL TIME"

    print(f"🔍 Searching for messages in {location_display}{sender_display} for {time_display}...")

    results = service.users().messages().list(userId="me", q=query, maxResults=10000).execute()
    messages = results.get("messages", [])

    if not messages:
        print(f"No messages found in {location_display}{sender_display} for {time_display}.")
        return

    print(f"Found {len(messages)} messages to delete from {location_display}{sender_display}.")
    batch_size = 999

    for i in range(0, len(messages), batch_size):
        batch = messages[i : i + batch_size]
        ids = [msg["id"] for msg in batch]
        print(f"🗑️  Deleting batch of {len(ids)} messages from {location_display}{sender_display}...")
        service.users().messages().batchDelete(userId="me", body={"ids": ids}).execute()

    print(f"✅ Successfully deleted {len(messages)} messages from {location_display}{sender_display} for {time_display}")


def print_warning(year, month, location, sender):
    """Print a very visible warning message"""
    location_display = "inbox" if location.lower() == "inbox" else f"label '{location}'"
    sender_display = f" from sender '{sender}'" if sender else ""

    if year and month:
        time_display = f"{year}-{month:02d}"
    elif year:
        time_display = f"year {year}"
    else:
        time_display = "ALL TIME"

    print("\n" + "=" * 70)
    print("= " + "⚠️  CRITICAL WARNING  ⚠️".center(66) + " =")
    print("=" * 70)
    print(f"  SCOPE:     {time_display}")
    print(f"  LOCATION:  {location_display}")
    if sender:
        print(f"  SENDER:    {sender}")
    print("=" * 70)
    print("  THIS WILL PERMANENTLY DELETE ALL MATCHING MESSAGES!")
    print("  THIS ACTION CANNOT BE UNDONE!")
    print("=" * 70 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Delete Gmail messages by filters: location (inbox/label), optional time period (year/month), and optional sender"
    )
    parser.add_argument("-y", "--year", type=int, help="Year (e.g., 2024). Omit to delete from all time")
    parser.add_argument("-m", "--month", type=int, choices=range(1, 13), help="Month (1–12). Requires --year")
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
        "-f", "--force", action="store_true", help="Skip confirmation prompt (NOT recommended)"
    )

    args = parser.parse_args()

    # Validate month requires year
    if args.month and not args.year:
        parser.error("--month requires --year to be specified")

    service = authenticate_gmail(args.credfile)

    # Show warning unless force flag is set
    if not args.force:
        print_warning(args.year, args.month, args.location, args.sender)
        confirm = input("Type 'DELETE' (all caps) to confirm: ")
        if confirm != "DELETE":
            print("Operation cancelled.")
            return
    else:
        print_warning(args.year, args.month, args.location, args.sender)
        print("⚠️  FORCE MODE: Skipping confirmation!\n")

    delete_messages_by_filters(service, args.year, args.month, args.location, args.sender)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nOperation cancelled by user.")
        sys.exit(0)
