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
        header = next(reader)  # Skip header
        
        print(f"DEBUG: Header columns: {header}")
        print(f"DEBUG: Loaded env vars: {list(env_vars.keys())}")

        print(f"\n{'Location':<30} | {'Extracted Env Vars':<35} | {'Resolved URL'}")
        print("-" * 100)
        
        seen_urls = set()  # Track already printed URLs
        
        for row in reader:
            if len(row) < 4: 
                continue
            
            call_info = row[0]
            
            # The URL pattern is in the last column (col3)
            raw_url = row[-1]
            
            if not raw_url:
                continue
            
            # Extract uppercase env variable patterns like {USERS_SERVICE_URL}
            # This ignores lowercase path params like {clubId}, {userId}
            env_matches = re.findall(r"\{([A-Z][A-Z0-9_]*_URL)\}", raw_url)
            
            if not env_matches:
                continue
            
            # Resolve env variables to their actual values
            resolved_url = raw_url
            all_found = True
            
            for env_var in env_matches:
                if env_var not in env_vars:
                    print(f"DEBUG: Missing env var: {env_var}")
                    all_found = False
                    break
                env_value = env_vars.get(env_var, "")
                # Wrap the resolved URL in curly braces: {http://localhost:3001}
                resolved_url = resolved_url.replace(f"{{{env_var}}}", f"{{{env_value}}}")
            
            if all_found:
                # Print only if all environment variables were found and resolved
                # Skip duplicates
                if resolved_url not in seen_urls:
                    seen_urls.add(resolved_url)
                    print(f"{call_info[:28]:<30} | {', '.join(env_matches):<35} | {resolved_url}")

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
    process_codeql_csv(r'C:\Users\mary\Clubs\Research\simple-app\my-research-project\codeql_results.csv', master_env)