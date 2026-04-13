import os
import re

# Get the directory where the script is located
script_dir = os.path.dirname(os.path.abspath(__file__))
# Construct the path to the input file
input_file_path = os.path.join(script_dir, 'tests', 'final_result.txt')

def parse_line(line):
    """Parses a line from the input file and extracts relevant information."""
    parts = [p.strip() for p in line.split('|')]
    if len(parts) < 4:
        return None
    
    caller_service = parts[1]
    url_match = re.search(r'\{(.*?)\}(.*)', parts[3])
    if not url_match:
        return None
        
    base_url, path = url_match.groups()
    
    # Determine target service from the start of the path
    path_parts = path.strip('/').split('/')
    target_service = path_parts[0] if path_parts else ''

    # Heuristic to determine HTTP method, defaulting to GET
    http_method = 'GET'
    if 'update' in path or 'unsubscribe' in path:
        http_method = 'POST'
    elif caller_service == 'gateway' and 'clubs' in path:
        http_method = 'POST'
    elif caller_service == 'gateway' and 'users' in path:
        http_method = 'POST'
    elif caller_service == 'events' and 'notifications' in path:
        http_method = 'POST'


    return {
        'caller': caller_service,
        'target': target_service,
        'path': path,
        'method': http_method
    }

def generate_plantuml(data):
    """Generates a PlantUML diagram from parsed data."""
    
    components = ['gateway', 'auth', 'users', 'clubs', 'events', 'notifications']
    
    # Filter out any components from the data that are not in the predefined list
    data = [d for d in data if d['caller'] in components and d['target'] in components]
    
    # Start of PlantUML diagram
    plantuml_string = "@startuml\n"
    plantuml_string += "!theme plain\n"
    plantuml_string += "left to right direction\n"
    plantuml_string += "skinparam componentStyle uml2\n"
    plantuml_string += "skinparam nodesep 20\n"
    plantuml_string += "skinparam ranksep 150\n\n"
    
    # Component alignment
    plantuml_string += "' Force all components to stay on the same horizontal rank\n"
    plantuml_string += "together {\n"
    for comp in components:
        plantuml_string += f"  component [{comp}] as {comp}\n"
    plantuml_string += "}\n\n"
    
    # Hidden links for ordering
    plantuml_string += "' Maintain the horizontal sequence\n"
    for i in range(len(components) - 1):
        plantuml_string += f"{components[i]} -[hidden]r- {components[i+1]}\n"
    plantuml_string += "\n"
    
    # Port definitions
    plantuml_string += "' --- Port Definitions ---\n\n"
    ports = {}
    port_counter = 1
    for comp in components:
        comp_ports = [d for d in data if d['target'] == comp]
        if comp_ports:
            plantuml_string += f"component {comp} {{\n"
            for i, port_data in enumerate(comp_ports):
                port_alias = f"{comp[0]}_p{i+1}"
                ports[(comp, port_data['path'])] = port_alias
                plantuml_string += f"    portin \"{port_data['path']}\" as {port_alias}\n"
            plantuml_string += "}\n\n"

    # Connections
    plantuml_string += "' --- Connections ---\n\n"
    for d in data:
        if d['target'] in components:
            target_port_alias = ports.get((d['target'], d['path']))
            if target_port_alias:
                plantuml_string += f"{d['caller']} --> {target_port_alias} : {d['method']}\n"

    plantuml_string += "@enduml\n"
    
    return plantuml_string

def main():
    """Main function to read data, parse it, and generate PlantUML."""
    try:
        with open(input_file_path, 'r') as f:
            lines = f.readlines()[2:]  # Skip header lines
    except FileNotFoundError:
        print(f"Error: {input_file_path} not found.")
        return

    parsed_data = []
    for line in lines:
        if line.strip():
            parsed_line = parse_line(line)
            if parsed_line:
                parsed_data.append(parsed_line)

    # Remove duplicate connections for cleaner diagram
    unique_data = [dict(t) for t in {tuple(d.items()) for d in parsed_data}]

    plantuml_output = generate_plantuml(unique_data)
    
    with open('diagram.puml', 'w') as f:
        f.write(plantuml_output)
        
    print("Successfully generated diagram.puml")

if __name__ == "__main__":
    main()
