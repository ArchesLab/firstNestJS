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


def infer_callee_service(env_matches):
    """Infer callee service name(s) from env var names like USERS_SERVICE_URL.

    Returns a lowercase service name (e.g. "users") or a comma-separated list
    if multiple distinct services are present, or "unknown" if none match
    the *_SERVICE_URL pattern.
    """
    services = set()
    for env_var in env_matches:
        m = re.match(r"([A-Z][A-Z0-9]*)_SERVICE_URL$", env_var)
        if m:
            services.add(m.group(1).lower())
    if not services:
        return "unknown"
    if len(services) == 1:
        return next(iter(services))
    return ",".join(sorted(services))


def process_codeql_csv(csv_path, env_vars, output_path):
    if not os.path.exists(csv_path):
        print(f"Error: CSV file {csv_path} not found.")
        return

    with open(csv_path, mode='r', encoding='utf-8') as f, \
         open(output_path, mode='w', encoding='utf-8') as out:
        reader = csv.reader(f)
        header = next(reader)  # Skip header

        print(f"DEBUG: Header columns: {header}")
        print(f"DEBUG: Loaded env vars: {list(env_vars.keys())}")

        # Try to locate callerService column (added by dataflow6.ql)
        try:
            caller_idx = header.index("callerService")
            http_method_idx = header.index("httpMethod")
        except ValueError as e:
            print(f"Error: Missing required column in CSV header - {e}")
            return

        header_line = f"{'Location':<30} | {'Caller Service':<15} | {'Extracted Env Vars':<35} | {'Resolved URL':<40} | {'HTTP Method'}"
        separator_line = "-" * 120
        print("\n" + header_line)
        print(separator_line)
        out.write(header_line + "\n")
        out.write(separator_line + "\n")
        
        # De-duplicate by (callerService, Extracted Env Vars, httpMethod)
        seen_tuples = set()
        
        for row in reader:
            if len(row) < 4: 
                continue
            
            call_info = row[0]
            caller_service = row[caller_idx]
            http_method = row[http_method_idx]
            
            # The URL pattern is in the second to last column (resolvedEndpoint)
            raw_url = row[-2]
            
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
                # De-duplicate rows with same (callerService, Extracted Env Vars, httpMethod)
                env_key = tuple(env_matches)
                key = (caller_service, env_key, http_method)

                if key not in seen_tuples:
                    seen_tuples.add(key)
                    line = (
                        f"{call_info[:28]:<30} | "
                        f"{caller_service:<15} | "
                        f"{', '.join(env_matches):<35} | "
                        f"{resolved_url:<40} | "
                        f"{http_method}"
                    )
                    print(line)
                    out.write(line + "\n")

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

    # Where to write the final results
    output_path = os.path.join(os.path.dirname(__file__), 'final_result.txt')
    
    # Run the processor
    process_codeql_csv(r'C:\Users\mary\Clubs\Research\simple-app\my-research-project\codeql_results.csv', master_env, output_path)