import win32com.client
import openpyxl
import datetime
import os
import re

# Function to clean text by removing special characters
def clean_string(text):
    return re.sub(r'[^a-zA-Z0-9\s]', '', text).lower().strip()

# Toggle for displaying first draft before sending the rest
display_first_draft = True  

# Define signature paths per division
signature_paths = {
    "xxxx": r"path/to/Signature.html",
    "xxxx": r"path/to/Signature.html",
    "xxxx": r"path/to/Signature.html"
}

# Toggle email sending per division (True = send, False = draft only)
send_toggle = {
    "xxxx": True,
    "xxxx": False,
    "xxxx": False
}

# Define BCC recipients per division
bcc_recipients = {
    "xxxx": "",  
    "xxxx": "bcc@example.com",
    "xxxx": ""  
}

# Define sender email per division
from_addresses = {
    "xxxx": "payments@xxxx.com",
    "xxxx": "payments@xxxx.com",
    "xxxx": "payments@xxxx.com"
}

# Define email subjects per division
email_subjects = {
    "xxxx": "Account Statement - xxxx Payments",
    "xxxx": "Account Statement - xxxx Payments",
    "xxxx": "Account Statement - xxxx Payments"
}

# Load Excel file
workbook = openpyxl.load_workbook(r"path/to/Statement.xlsx")
sheet = workbook.active

# Today's date
today = datetime.date.today()

# Initialize logs
valid_rows = []
drafted_divisions = set()

# 1st Phase: Pre-checks
for row in sheet.iter_rows(min_row=2, values_only=True):
    merchant_id, recipient_email, salutation, attachment_path, _, division = row

    # Validate division
    division = str(division).strip().lower()
    if division not in signature_paths:
        continue

    # Check if attachment exists
    if not os.path.exists(attachment_path):
        continue
    
    # Clean salutation and file path
    salutation_fragment = clean_string(salutation.split(",")[0].replace("Dear ", ""))
    attachment_file_name = clean_string(os.path.basename(attachment_path))

    # Validate salutation in file name
    if salutation_fragment not in attachment_file_name:
        continue

    valid_rows.append((row, division))

# Exit if no valid emails to process
if not valid_rows:
    print("No valid emails to process. Exiting.")
    workbook.close()
    exit()

# 2nd Phase: Send or display emails
ol = win32com.client.Dispatch("Outlook.Application")
emails_sent_count = 0

for row_data in valid_rows:
    row, division = row_data
    merchant_id, recipient_email, salutation, attachment_path, _, division = row

    # Get signature
    signature_path = signature_paths[division]
    with open(signature_path, 'r', encoding='utf-8') as signature_file:
        signature = signature_file.read()

    should_send_email = send_toggle[division]
    bcc_recipient = bcc_recipients[division]
    from_email = from_addresses[division]

    # Last month logic
    last_day_of_previous_month = today.replace(day=1) - datetime.timedelta(days=1)
    previous_month = last_day_of_previous_month.strftime('%b').upper()
    previous_year = last_day_of_previous_month.strftime('%Y')

    email_subject = f"{email_subjects[division]} {previous_month} {previous_year}"

    # Create email
    newmail = ol.CreateItem(0)
    newmail.Subject = email_subject
    newmail.To = recipient_email
    if bcc_recipient:
        newmail.Bcc = bcc_recipient

    body_text = f"{salutation}\n\nYour account statement is attached. Please let us know if you have any questions."
    
    newmail.Body = body_text.strip()
    newmail.SentOnBehalfOfName = from_email
    newmail.Attachments.Add(attachment_path)
    newmail.HTMLBody += '<br>' + signature

    # Display one draft per division
    if division not in drafted_divisions:
        newmail.Display()
        drafted_divisions.add(division)

# Confirmation before sending
if drafted_divisions:
    permission = input(f"Review completed for drafts ({', '.join(drafted_divisions)}). Type 'yes' to send: ").strip().lower()
    if permission != 'yes':
        print("Process aborted. No emails sent.")
        workbook.close()
        exit()

# Send remaining emails
for row_data in valid_rows:
    row, division = row_data
    merchant_id, recipient_email, salutation, attachment_path, _, division = row

    # Get signature again
    signature_path = signature_paths[division]
    with open(signature_path, 'r', encoding='utf-8') as signature_file:
        signature = signature_file.read()

    should_send_email = send_toggle[division]
    bcc_recipient = bcc_recipients[division]
    from_email = from_addresses[division]

    body_text = f"{salutation}\n\nYour account statement is attached. Please let us know if you have any questions."

    newmail = ol.CreateItem(0)
    newmail.Subject = email_subject
    newmail.To = recipient_email
    if bcc_recipient:
        newmail.Bcc = bcc_recipient

    newmail.Body = body_text.strip()
    newmail.SentOnBehalfOfName = from_email
    newmail.Attachments.Add(attachment_path)
    newmail.HTMLBody += '<br>' + signature

    if should_send_email:
        newmail.Send()
        emails_sent_count += 1
        print(f"Email sent to {recipient_email} from {from_email}")
    else:
        newmail.Save()
        print(f"Draft saved for {recipient_email} (Division: {division.upper()})")

print(f"\nTotal emails sent: {emails_sent_count}")
workbook.close()
