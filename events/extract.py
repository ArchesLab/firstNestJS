import os
from dotenv import load_dotenv

# This 'engine' finds the .env file and loads the variables
load_dotenv() 

ports = {}
urls = {}

for key, value in os.environ.items():
    key_upper = key.upper()
    if "URL" in key_upper:
        urls[key] = value  # Stores as {'DB_URL': 'postgres://...'}
    elif "PORT" in key_upper:
        ports[key] = value # Stores as {'APP_PORT': '8080'}

print(f"Detected Ports: {ports}")
print(f"Detected URLs: {urls}")