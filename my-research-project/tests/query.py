import csv
import os
import re

def load_all_envs(env_paths):
    """Takes a list of paths and merges them into one dictionary."""
    combined_vars = {}
    
    for path in env_paths:
        if not os.path.exists(path):
            print(f"Skipping: {path} (Not found)")
            continue
            
        print(f"Loading variables from: {path}")
        with open(path, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'): continue
                if '=' in line:
                    key, value = line.split('=', 1)
                    # Clean up the key and value
                    combined_vars[key.strip()] = value.strip().strip('"').strip("'")
                    
    return combined_vars

def process_codeql_csv(csv_path, env_vars):
    if not os.path.exists(csv_path):
        print(f"Error: CSV file {csv_path} not found.")
        return

    with open(csv_path, mode='r', encoding='utf-8') as f:
        reader = csv.reader(f)
        next(reader) 

        print(f"\n{'CodeQL Match':<20} | {'Extracted Var':<25} | {'Resolved URL'}")
        print("-" * 90)
        
        for row in reader:
            if len(row) < 2: continue
            
            call_info = row[0]
            raw_url = row[1]

            match = re.search(r"\{(.*?)\}", raw_url)
            
            if match:
                var_name = match.group(1)
                # Now looks through the combined dictionary from ALL env files
                env_value = env_vars.get(var_name, f"MISSING[{var_name}]")
                
                resolved_url = raw_url.replace(f"{{{var_name}}}", env_value).replace("Final URL: ", "")
                print(f"{call_info[:18]:<20} | {var_name:<25} | {resolved_url}")
            else:
                print(f"{call_info[:18]:<20} | {'No {VAR} found':<25} | {raw_url}")

if __name__ == "__main__":
    # List all the different locations where your .env files are stored
    env_locations = [
        r"C:\Users\mary\Clubs\Research\simple-app\events\.env",
        r"C:\Users\mary\Clubs\Research\simple-app\users\.env",
        r"C:\Users\mary\Clubs\Research\simple-app\notifications\.env",
        r"C:\Users\mary\Clubs\Research\simple-app\clubs\.env"
    ]
    
    # Load all of them into one master dictionary
    master_env = load_all_envs(env_locations)
    
    # Run the processor
    process_codeql_csv('codeql_results.csv', master_env)