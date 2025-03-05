import requests
import pandas as pd
import os

# Fetch API key from environment variables (replace with your method of secure storage)
api_key = os.getenv("GOOGLE_API_KEY")

def get_timezone(address):
    if not api_key:
        print("Error: Google API Key not found. Set GOOGLE_API_KEY as an environment variable.")
        return None

    try:
        # Get latitude and longitude
        geocode_url = f'https://maps.googleapis.com/maps/api/geocode/json?address={address}&key={api_key}'
        geocode_response = requests.get(geocode_url)
        geocode_data = geocode_response.json()
        
        if geocode_data.get('status') == 'OK':
            location = geocode_data['results'][0]['geometry']['location']
            lat = location['lat']
            lng = location['lng']
            
            # Get timezone
            timezone_url = f'https://maps.googleapis.com/maps/api/timezone/json?location={lat},{lng}&timestamp=0&key={api_key}'
            timezone_response = requests.get(timezone_url)
            timezone_data = timezone_response.json()
            
            if timezone_data.get('status') == 'OK':
                return timezone_data['timeZoneId']
    except Exception as e:
        print(f"Error processing address '{address}': {e}")
    
    return None

# Load Excel file
input_file = r'path/to/TZaddresses.xlsx'
output_file_path = r'path/to/output_file.txt'

df = pd.read_excel(input_file)
addresses = df['Address'].tolist()

# Write results to a text file
with open(output_file_path, "w") as output_file:
    for address in addresses:
        timezone = get_timezone(address)
        if timezone:
            output_file.write(f"Timezone for {address}: {timezone}\n")
        else:
            output_file.write(f"No timezone data found for {address}\n")

print("Timezone data has been written to", output_file_path)
