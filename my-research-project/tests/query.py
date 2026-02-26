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

        print(f"\n{'Location':<30} | {'Extracted Env Vars':<35} | {'Resolved URL'}")
        print("-" * 100)
        
        for row in reader:
            if len(row) < 2: 
                continue
            
            call_info = row[0]
            
            # Find the column that contains "Final URL:"
            raw_url = None
            for col in row[1:]:
                if "Final URL:" in str(col):
                    raw_url = col
                    break
            
            if raw_url is None:
                continue
            
            # Only process lines that contain ENV_LOOKUP
            if "ENV_LOOKUP" not in raw_url:
                continue

            # Extract all ENV_LOOKUP{VAR_NAME} patterns
            env_matches = re.findall(r"ENV_LOOKUP\{([^}]+)\}", raw_url)
            
            if not env_matches:
                continue
            
            # Resolve all ENV_LOOKUP variables to their actual values
            resolved_url = raw_url.replace("Final URL: ", "")
            all_found = True
            
            for env_var in env_matches:
                if env_var not in env_vars:
                    all_found = False
                    break
                env_value = env_vars.get(env_var, "")
                resolved_url = resolved_url.replace(f"ENV_LOOKUP{{{env_var}}}", env_value)
            
            if all_found:
                # Print only if all environment variables were found and resolved
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