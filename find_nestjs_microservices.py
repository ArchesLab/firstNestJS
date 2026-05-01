#!/usr/bin/env python3
"""Query GitHub's GraphQL API to find NestJS microservice repositories with specific protocols."""

import json
import os
import sys
import urllib.request

GITHUB_GRAPHQL_URL = "https://api.github.com/graphql"

# Template for searching repository metadata
REPO_QUERY = """
query FindNestJSMicroservices($queryString: String!, $cursor: String) {
  search(query: $queryString, type: REPOSITORY, first: 20, after: $cursor) {
    repositoryCount
    pageInfo {
      hasNextPage
      endCursor
    }
    nodes {
      ... on Repository {
        nameWithOwner
        description
        url
        stargazerCount
        primaryLanguage {
          name
        }
      }
    }
  }
}
"""

# Template for searching inside code (package.json and imports)
CODE_SEARCH_QUERY = """
query FindNestJSImports($queryString: String!, $cursor: String) {
  search(query: $queryString, type: CODE, first: 20, after: $cursor) {
    codeCount
    pageInfo {
      hasNextPage
      endCursor
    }
    nodes {
      ... on CodeSearchResult {
        repository {
          nameWithOwner
          description
          url
          stargazerCount
          primaryLanguage {
            name
          }
        }
      }
    }
  }
}
"""

# Targeting the specific package inside the code + the communication protocols
SEARCH_QUERIES = [
    # 1. Deep Search: find "@nestjs/microservices" inside package.json with the protocols
    {
        "query": '"@nestjs/microservices" (axios OR grpc OR redis) path:package.json',
        "type": "CODE",
    },
    # 2. Deep Search: find "@nestjs/microservices" imports in TypeScript files
    {
        "query": 'import "@nestjs/microservices" (axios OR grpc OR redis) language:TypeScript',
        "type": "CODE",
    },
    # 3. Fallback: find repositories tagged or described with these terms
    {
        "query": 'nestjs microservice (axios OR grpc OR redis) stars:>=5',
        "type": "REPOSITORY",
    },
]

def graphql_request(token: str, query: str, variables: dict) -> dict:
    payload = json.dumps({"query": query, "variables": variables}).encode()
    req = urllib.request.Request(
        GITHUB_GRAPHQL_URL,
        data=payload,
        headers={
            "Authorization": f"bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "NestSearchBot",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())

def search_github(token: str, search_query: str, search_type: str, max_pages: int = 2):
    cursor = None
    all_repos = []
    gql = CODE_SEARCH_QUERY if search_type == "CODE" else REPO_QUERY

    for _ in range(max_pages):
        variables = {"queryString": search_query, "cursor": cursor}
        result = graphql_request(token, gql, variables)

        if "errors" in result:
            print(f"  GraphQL errors: {result['errors']}", file=sys.stderr)
            break

        search_data = result["data"]["search"]
        for node in search_data["nodes"]:
            if not node: continue
            # Handle nesting difference between CODE search and REPO search
            repo_node = node["repository"] if search_type == "CODE" else node
            if repo_node:
                all_repos.append(repo_node)

        if not search_data["pageInfo"]["hasNextPage"]:
            break
        cursor = search_data["pageInfo"]["endCursor"]

    return all_repos

def main():
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        print("Error: Set the GITHUB_TOKEN environment variable.", file=sys.stderr)
        sys.exit(1)

    seen = set()
    unique_repos = []

    for entry in SEARCH_QUERIES:
        print(f"Searching: {entry['query']}...")
        results = search_github(token, entry["query"], entry["type"])
        
        for repo in results:
            name_with_owner = repo["nameWithOwner"]
            # Apply Filter: >= 5 stars and deduplicate
            if name_with_owner not in seen and repo.get("stargazerCount", 0) >= 5:
                seen.add(name_with_owner)
                
                # Split owner and name
                owner, name = name_with_owner.split('/')
                
                # Format to only the 6 requested fields
                unique_repos.append({
                    "name": name,
                    "owner": owner,
                    "description": repo.get("description") or "No description",
                    "url": repo.get("url"),
                    "primaryLanguage": (repo.get("primaryLanguage") or {}).get("name", "N/A"),
                    "stargazerCount": repo.get("stargazerCount")
                })

    # Sort results by stars descending
    unique_repos.sort(key=lambda r: r["stargazerCount"], reverse=True)

    # Console Output
    print(f"\nFound {len(unique_repos)} repositories matching criteria:\n")
    for r in unique_repos:
        print(f"Repo: {r['owner']}/{r['name']}")
        print(f"Stars: {r['stargazerCount']} | Lang: {r['primaryLanguage']}")
        print(f"URL: {r['url']}")
        print(f"Desc: {r['description'][:100]}...")
        print("-" * 40)

    # Save to JSON
    with open("nestjs_microservices.json", "w") as f:
        json.dump(unique_repos, f, indent=2)
    print(f"\nSaved results to nestjs_microservices.json")

if __name__ == "__main__":
    main()