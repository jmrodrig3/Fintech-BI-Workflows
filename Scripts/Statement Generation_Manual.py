import pandas as pd
from pathlib import Path
import win32com.client as win32
import re

# Paths to input files
input_files = [
    r"path/to/Account_Info.csv",
    r"path/to/SUMMARY.csv",
    r"path/to/DEPOSIT_DETAIL.csv",
    r"path/to/PLATFORM_FEES.csv",
    r"path/to/CHARGES.csv"
]

# Specify target Merchant IDs for file creation (Populate externally)
target_merchant_ids = []

# Path to save grouped files
output_folder = Path(r"path/to/output_folder")
output_folder.mkdir(parents=True, exist_ok=True)

# Load files into dataframes
dfs = [pd.read_csv(file) for file in input_files]
sheet_names = ["Account Info", "Summary", "Deposit Detail", "Platform Fees", "Charges"]

# Initialize counters and dictionary to track merchant names
file_count = 0
merchant_name_count = {}

# Function to sanitize filenames by removing forbidden characters
def sanitize_filename(name):
    return re.sub(r'[<>:"/\\|?*]', '', name)

# Check if the first file has 'Merchant ID' column for grouping
if 'Merchant ID' in dfs[0].columns and 'Merchant Name' in dfs[0].columns:
    for merchant_id, group_data in dfs[0].groupby('Merchant ID'):
        if merchant_id not in target_merchant_ids:
            continue

        # Sanitize the merchant name and construct the unique file name
        merchant_name = sanitize_filename(group_data['Merchant Name'].iloc[0])
        unique_file_name = f"{merchant_name}_{merchant_id}_Statement.pdf"
        pdf_path = output_folder / unique_file_name

        # Remove any existing file with the same name
        if pdf_path.exists():
            pdf_path.unlink()

        # Prepare a temporary Excel workbook for PDF conversion
        excel_app = win32.DispatchEx('Excel.Application')
        excel_app.Visible = False
        wb = excel_app.Workbooks.Add()

        try:
            # Create and populate sheets
            for sheet_name, df in zip(sheet_names, dfs):
                merchant_data = df[df['Merchant ID'] == merchant_id]
                if sheet_name != "Account Info":
                    merchant_data = merchant_data.drop(columns=['Merchant ID', 'Merchant Name'], errors='ignore')
                
                ws = wb.Sheets.Add(After=wb.Sheets(wb.Sheets.Count))
                ws.Name = sheet_name

                # Write headers
                ws.Cells(1, 1).Value = "Company Name Here"
                ws.Cells(2, 1).Value = "Company Address Here"
                ws.Cells(3, 1).Value = "City, State, ZIP Code"
                ws.Cells(4, 1).Value = "+1 XXX-XXX-XXXX"
                ws.Cells(5, 1).Value = "Statement Period: MM-DD-YYYY to MM-DD-YYYY"
                
                ws.Cells(7, 1).Value = sheet_name
                ws.Cells(7, 1).Font.Bold = True
                ws.Cells(7, 1).Font.Size = 14
                
                start_row = 9
                for col_num, column_title in enumerate(merchant_data.columns, start=1):
                    ws.Cells(start_row, col_num).Value = column_title
                    ws.Cells(start_row, col_num).Font.Bold = True

                for row_num, row_data in enumerate(merchant_data.itertuples(index=False), start=start_row + 1):
                    for col_num, cell_value in enumerate(row_data, start=1):
                        ws.Cells(row_num, col_num).Value = cell_value

                ws.Columns.AutoFit()
                if sheet_name != "Account Info":
                    ws.Columns(1).ColumnWidth = 20

                ws.PageSetup.Orientation = 2
                ws.PageSetup.Zoom = False
                ws.PageSetup.FitToPagesWide = 1

            # Convert to PDF
            wb.ExportAsFixedFormat(0, str(pdf_path))

            # Track created files with merchant name
            merchant_name_count[merchant_name] = merchant_name_count.get(merchant_name, 0) + 1

            # Count successful file creation
            file_count += 1

        except Exception as e:
            print(f"Failed to create PDF for {merchant_id}: {e}")
        
        finally:
            wb.Close(False)
            excel_app.Quit()

# Final file renaming based on duplicate check
for pdf_file in output_folder.glob("*.pdf"):
    match = re.match(r"(.*)_(mer_[a-zA-Z0-9]+)_Statement.pdf", pdf_file.name)
    if match:
        merchant_name, merchant_id = match.groups()
        if merchant_name_count.get(merchant_name, 0) == 1:
            new_name = f"{merchant_name}_Statement.pdf"
            pdf_file.rename(output_folder / new_name)

# Final summary
print(f"Process completed. {file_count} files were created and saved to:", output_folder)
