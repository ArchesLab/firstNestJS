import os
import json
import subprocess
from dotenv import load_dotenv

# Load variables from .env file
load_dotenv()

def get_ast_grep_matches(rule_path, target_dir):
    # Run ast-grep and output as JSON
    # 'shell=True' is often required on Windows to find the 'sg' executable
    result = subprocess.run(
        ['sg', 'scan', '-r', rule_path, target_dir, '--json'],
        capture_output=True,
        text=True,
        shell=True
    )
    
    if result.returncode != 0:
        print(f"ast-grep Error: {result.stderr}")
        return set()

    try:
        matches = json.loads(result.stdout)
        found_matches = set()
        
        for match in matches:
            # 'text' is the actual string found in code (e.g., 'CLUBS_SERVICE_URL')
            raw_text = match.get('text', '').strip()
            if raw_text:
                # Remove quotes so "'KEY'" becomes "KEY"
                # This allows it to match the keys found in os.environ
                clean_text = raw_text.strip("'\"")
                found_matches.add(clean_text)
                
        return found_matches
    except json.JSONDecodeError:
        # If result.stdout is empty, it means no matches were found
        return set()

# 1. Get keys from .env
# Filter for keys containing "URL" to match your logic
env_url_keys = {key for key in os.environ.keys() if "URL" in key.upper()}

# 2. Get keys from TS code using the rule
# Use 'r' before the string to prevent (unicode error)
rule_file = r'.\rules\url-rules.yml'
source_file = r'.\src\app.service.ts'

code_url_keys = get_ast_grep_matches(rule_file, source_file)

# 3. Comparison Logic
are_the_same = env_url_keys == code_url_keys

print("-" * 30)
print(f"Env Keys:  {env_url_keys}")
print(f"Code Keys: {code_url_keys}")
print(f"Match:     {are_the_same}")
print("-" * 30)

if not are_the_same:
    missing_in_code = env_url_keys - code_url_keys
    missing_in_env = code_url_keys - env_url_keys
    if missing_in_code:
        print(f"Missing in Code: {missing_in_code}")
    if missing_in_env:
        print(f"Missing in Env:  {missing_in_env}")