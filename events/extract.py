import csv
import re
import os

def resolve_environment_mapping(csv_input, env_path):
    # 1. Parse the .env file
    env_map = {}
    if os.path.exists(env_path):
        with open(env_path, 'r') as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    k, v = line.split('=', 1)
                    env_map[k.strip()] = v.strip().strip('"').strip("'")
    else:
        print(f"CRITICAL ERROR: .env file not found at {env_path}")
        return

    print(f"--- Successfully loaded {len(env_map)} variables from {env_path} ---")
    print(f"{'Location':<30} | {'Resolved URL'}")
    print("-" * 80)

    # 2. Process CodeQL Results
    with open(csv_input, mode='r', encoding='utf-8') as f:
        reader = csv.reader(f)
        # Skip the header row (the one that says "axiosCall", "col1")
        next(reader, None) 
        
        for row in reader:
            if not row: continue
            
            location = row[0]
            # row[1] is: "Final URL: {USERS_SERVICE_URL}/users"
            raw_message = row[1] 
            
            # Extract keys inside { }
            keys = re.findall(r'\{([A-Z0-9_]+)\}', raw_message)
            
            # Clean up the "Final URL: " prefix for a prettier report
            resolved_url = raw_message.replace("Final URL: ", "")
            
            for key in keys:
                actual_value = env_map.get(key)
                if actual_value:
                    resolved_url = resolved_url.replace(f"{{{key}}}", actual_value)
                else:
                    resolved_url = resolved_url.replace(f"{{{key}}}", f"<< MISSING: {key} >>")

            print(f"{location[:30]:<30} | {resolved_url}")

# --- Updated Path Section ---

# 1. The root directory of your project
BASE_PATH = r"C:\Users\mary\Clubs\Research\simple-app"

# 2. Points to: C:\Users\mary\Clubs\Research\simple-app\my-research-project\codeql_results.csv
CSV_FILE = os.path.join(BASE_PATH, "my-research-project", "codeql_results.csv")

# 3. Points to: C:\Users\mary\Clubs\Research\simple-app\events\.env
# We pass "events" as a folder name, then ".env" as the filename
ENV_FILE = os.path.join(BASE_PATH, "events", ".env") 

# Run the analysis with these paths
resolve_environment_mapping(CSV_FILE, ENV_FILE)