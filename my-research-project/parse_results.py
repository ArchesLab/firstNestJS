import json
import os
import glob
from collections import defaultdict
from statistics import mean, stdev

def parse_codeql_logs(log_dir):
    predicate_times = defaultdict(list)
    total_wall_clocks = []

    # Get all log files from the 30 runs
    log_files = glob.glob(os.path.join(log_dir, "log_*.json"))
    
    if not log_files:
        print(f"No log files found in {log_dir}. Did the benchmark finish?")
        return

    for file_path in log_files:
        with open(file_path, 'r') as f:
            try:
                # CodeQL logs are often lists of event objects
                data = json.load(f)
                
                # Check if it's a list of events or a structured object
                events = data if isinstance(data, list) else data.get('events', [])
                
                for event in events:
                    # 1. Capture Predicate-specific timing
                    if 'predicateName' in event:
                        name = event['predicateName']
                        # 'millis' is the standard field for duration in CodeQL logs
                        time = event.get('millis', 0)
                        predicate_times[name].append(time)
                    
                    # 2. Capture Total Evaluation Wall Clock (Internal)
                    if event.get('kind') == 'evaluation' or event.get('task') == 'evaluation':
                        total_wall_clocks.append(event.get('millis', 0))
                        
            except Exception as e:
                print(f"Skipping {file_path} due to error: {e}")

    # Output the Table
    print("\n" + "="*85)
    print(f"{'Predicate Name':<55} | {'Avg (ms)':<12} | {'Std Dev':<10}")
    print("-" * 85)
    
    # Sort by longest running predicates first
    sorted_preds = sorted(predicate_times.items(), key=lambda x: mean(x[1]), reverse=True)
    
    for pred, times in sorted_preds:
        # Filter out tiny predicates (< 1ms) to keep the report clean
        avg_time = mean(times)
        if avg_time > 1: 
            sd = stdev(times) if len(times) > 1 else 0
            # Clean up long predicate names for readability
            display_name = (pred[:52] + '..') if len(pred) > 54 else pred
            print(f"{display_name:<55} | {avg_time:<12.2f} | {sd:.2f}")

    if total_wall_clocks:
        avg_total_s = mean(total_wall_clocks) / 1000
        print("-" * 85)
        print(f"AVERAGE INTERNAL EVALUATION WALL CLOCK: {avg_total_s:.4f} seconds")
    print("="*85 + "\n")

if __name__ == "__main__":
    # Ensure this matches the folder in your PowerShell script
    parse_codeql_logs("./evaluator-logs")