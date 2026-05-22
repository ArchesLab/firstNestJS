#!/usr/bin/env python3
"""Find GitHub repositories that likely use raw axios in NestJS services.

Set GITHUB_TOKEN before running:
    PowerShell: $env:GITHUB_TOKEN = "ghp_..."
    Bash:       export GITHUB_TOKEN="ghp_..."
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


GITHUB_CODE_SEARCH_URL = "https://api.github.com/search/code"
GITHUB_REPOSITORY_SEARCH_URL = "https://api.github.com/search/repositories"
GITHUB_REPOS_URL = "https://api.github.com/repos"
OUTPUT_FILE = "repositories.json"
MIN_STARS = 5
PER_PAGE = 50
MAX_CODE_PAGES = 1
MAX_REPOSITORY_PAGES = 1
PAUSE_SECONDS = 2.0

EXCLUDED_REPO_TERMS = {
    "awesome",
    "boilerplate",
    "cookbook",
    "demo",
    "example",
    "examples",
    "exercise",
    "kata",
    "learn",
    "learning",
    "playground",
    "sample",
    "samples",
    "scaffold",
    "seed",
    "starter",
    "template",
    "tutorial",
    "rabbitmq",
}
EXCLUDED_LIBRARY_TERMS = {
    "adapter",
    "client library",
    "component library",
    "helper library",
    "library for",
    "package",
    "plugin",
    "sdk",
    "toolkit",
    "wrapper",
}
EXCLUDED_PATH_PARTS = {
    "demo",
    "demos",
    "example",
    "examples",
    "sample",
    "samples",
    "starter",
    "template",
    "tutorial",
}

# GitHub code search works best here as a recall stage, not a perfect
# classifier. The local target shape is "NestJS services communicating via raw
# axios", but exact queries like `"configService.get" "axios.get"` are too
# brittle. This script collects evidence and filters in Python:
#
#   required: at least one raw axios signal
#   required: at least one NestJS signal
#   optional: microservice/monorepo signals raise the confidence score
#
# That gives you more candidates to run the Axios connector against without
# admitting every random TypeScript repo that happens to import axios.
SEARCH_QUERIES = [
    # Raw axios calls in Nest injectable/controller files.
    {
        "query": '"axios.get" "@Injectable" language:TypeScript',
        "type": "CODE",
        "evidence": ["RAW_AXIOS_CALL"],
    },
    {
        "query": '"axios.post" "@Injectable" language:TypeScript',
        "type": "CODE",
        "evidence": ["RAW_AXIOS_CALL"],
    },
    {
        "query": '"axios.put" "@Injectable" language:TypeScript',
        "type": "CODE",
        "evidence": ["RAW_AXIOS_CALL"],
    },
    {
        "query": '"axios.patch" "@Injectable" language:TypeScript',
        "type": "CODE",
        "evidence": ["RAW_AXIOS_CALL"],
    },
    {
        "query": '"axios.delete" "@Injectable" language:TypeScript',
        "type": "CODE",
        "evidence": ["RAW_AXIOS_CALL"],
    },
    {
        "query": '"axios.request" "@Injectable" language:TypeScript',
        "type": "CODE",
        "evidence": ["RAW_AXIOS_CALL"],
    },
    {
        "query": '"axios.get" "@nestjs/common" language:TypeScript',
        "type": "CODE",
        "evidence": ["RAW_AXIOS_CALL", "NESTJS_SOURCE"],
    },
    {
        "query": '"axios.post" "@nestjs/common" language:TypeScript',
        "type": "CODE",
        "evidence": ["RAW_AXIOS_CALL", "NESTJS_SOURCE"],
    },

    # Raw axios imports or custom instances in Nest source.
    {
        "query": '"import axios" "@nestjs/common" language:TypeScript',
        "type": "CODE",
        "evidence": ["RAW_AXIOS_IMPORT", "NESTJS_SOURCE"],
    },
    {
        "query": '"from \\"axios\\"" "@nestjs/common" language:TypeScript',
        "type": "CODE",
        "evidence": ["RAW_AXIOS_IMPORT", "NESTJS_SOURCE"],
    },
    {
        "query": '"axios.create" "@Injectable" language:TypeScript',
        "type": "CODE",
        "evidence": ["RAW_AXIOS_CALL"],
    },
    {
        "query": '"axios.create" "@nestjs/common" language:TypeScript',
        "type": "CODE",
        "evidence": ["RAW_AXIOS_CALL", "NESTJS_SOURCE"],
    },

    # package.json evidence that the repo depends on NestJS and axios.
    {
        "query": '"@nestjs/core" "axios" filename:package.json',
        "type": "CODE",
        "evidence": ["AXIOS_PACKAGE", "NESTJS_PACKAGE"],
    },
    {
        "query": '"@nestjs/microservices" "axios" filename:package.json',
        "type": "CODE",
        "evidence": ["AXIOS_PACKAGE", "NESTJS_PACKAGE", "NEST_MICROSERVICE"],
    },

    # Optional microservice signals. These boost confidence but are not
    # mandatory, because raw-axios microservice repos often do not use
    # @nestjs/microservices at all.
    {
        "query": '"@nestjs/microservices" "Transport." language:TypeScript',
        "type": "CODE",
        "evidence": ["NEST_MICROSERVICE"],
    },
    {
        "query": '"@nestjs/microservices" "@MessagePattern" language:TypeScript',
        "type": "CODE",
        "evidence": ["NEST_MICROSERVICE"],
    },
    {
        "query": '"connectMicroservice" "Transport." language:TypeScript',
        "type": "CODE",
        "evidence": ["NEST_MICROSERVICE"],
    },
    {
        "query": '"createMicroservice" "@nestjs/microservices" language:TypeScript',
        "type": "CODE",
        "evidence": ["NEST_MICROSERVICE"],
    },

    # Repository metadata searches catch projects whose code search results are
    # incomplete or rate-limited.
    {
        "query": "nestjs axios microservice language:typescript stars:>=5 pushed:>2023-01-01",
        "type": "REPOSITORY",
        "evidence": ["REPO_AXIOS_TOPIC", "NESTJS_PACKAGE", "REPO_MICROSERVICE_TOPIC"],
    },
    {
        "query": "nestjs axios microservices in:name,description,topics stars:>=5",
        "type": "REPOSITORY",
        "evidence": ["REPO_AXIOS_TOPIC", "NESTJS_PACKAGE", "REPO_MICROSERVICE_TOPIC"],
    },
    {
        "query": "nestjs axios monorepo in:name,description,topics stars:>=5",
        "type": "REPOSITORY",
        "evidence": ["REPO_AXIOS_TOPIC", "NESTJS_PACKAGE", "MULTI_SERVICE_LAYOUT"],
    },
]

AXIOS_EVIDENCE = {"RAW_AXIOS_CALL", "RAW_AXIOS_IMPORT", "REPO_AXIOS_TOPIC"}
NESTJS_EVIDENCE = {"NESTJS_SOURCE", "NESTJS_PACKAGE", "NEST_MICROSERVICE"}
EVIDENCE_WEIGHTS = {
    "RAW_AXIOS_CALL": 4,
    "RAW_AXIOS_IMPORT": 3,
    "REPO_AXIOS_TOPIC": 2,
    "AXIOS_PACKAGE": 2,
    "NESTJS_SOURCE": 3,
    "NESTJS_PACKAGE": 3,
    "NEST_MICROSERVICE": 2,
    "MULTI_SERVICE_LAYOUT": 2,
    "REPO_MICROSERVICE_TOPIC": 1,
}
MIN_EVIDENCE_SCORE = 5


def github_get(token: str, url: str) -> dict[str, Any]:
    """Send one GitHub REST request and return the decoded JSON response."""
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "nestjs-axios-repository-search",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"GitHub REST request failed: HTTP {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"GitHub REST request failed: {exc.reason}") from exc


def search_code(
    token: str,
    search_query: str,
    max_pages: int = MAX_CODE_PAGES,
    pause_seconds: float = PAUSE_SECONDS,
) -> list[dict[str, Any]]:
    """Run one REST code search query and return matching code items."""
    items: list[dict[str, Any]] = []

    for page in range(1, max_pages + 1):
        params = urllib.parse.urlencode(
            {"q": search_query, "per_page": PER_PAGE, "page": page}
        )
        result = github_get(token, f"{GITHUB_CODE_SEARCH_URL}?{params}")
        total_count = result.get("total_count", 0)

        if page == 1:
            print(f"  totalCount: {total_count}")

        page_items = result.get("items", [])
        items.extend(page_items)

        if len(items) >= total_count or not page_items:
            break

        time.sleep(pause_seconds)

    return items


def search_repositories(
    token: str,
    search_query: str,
    max_pages: int = MAX_REPOSITORY_PAGES,
    pause_seconds: float = PAUSE_SECONDS,
) -> list[dict[str, Any]]:
    """Run one REST repository search query and return repository items."""
    repositories: list[dict[str, Any]] = []

    for page in range(1, max_pages + 1):
        params = urllib.parse.urlencode(
            {"q": search_query, "per_page": PER_PAGE, "page": page}
        )
        result = github_get(token, f"{GITHUB_REPOSITORY_SEARCH_URL}?{params}")
        total_count = result.get("total_count", 0)

        if page == 1:
            print(f"  totalCount: {total_count}")

        page_items = result.get("items", [])
        repositories.extend(page_items)

        if len(repositories) >= total_count or not page_items:
            break

        time.sleep(pause_seconds)

    return repositories


def fetch_repository(token: str, name_with_owner: str) -> dict[str, Any]:
    """Fetch complete repository metadata, including stargazers_count."""
    quoted_name = urllib.parse.quote(name_with_owner, safe="/")
    return github_get(token, f"{GITHUB_REPOS_URL}/{quoted_name}")


def evidence_score(evidence: set[str]) -> int:
    """Compute a lightweight confidence score for candidate ranking."""
    return sum(EVIDENCE_WEIGHTS.get(item, 0) for item in evidence)


def project_exclusion_reason(repo: dict[str, Any]) -> str | None:
    """Return why a repo should be excluded from project candidates."""
    name = repo.get("full_name", "").lower()
    description = (repo.get("description") or "").lower()
    topics = [str(topic).lower() for topic in repo.get("topics", [])]
    metadata_text = " ".join([name, description, *topics])

    for term in sorted(EXCLUDED_REPO_TERMS):
        if term in metadata_text:
            return f"metadata contains '{term}'"

    for term in sorted(EXCLUDED_LIBRARY_TERMS):
        if term in metadata_text:
            return f"metadata looks like a library: '{term}'"

    if "library" in name and "library-management" not in name:
        return "repository name looks like a library package"

    matched_paths = repo.get("matchedPaths", set())
    if matched_paths:
        relevant_paths = [
            path.lower().replace("\\", "/")
            for path in matched_paths
            if path
        ]
        example_paths = [
            path
            for path in relevant_paths
            if any(f"/{part}/" in f"/{path}/" for part in EXCLUDED_PATH_PARTS)
        ]
        if len(example_paths) == len(relevant_paths):
            return "all code matches are under example/demo/template paths"

    return None


def normalize_repository(repo: dict[str, Any]) -> dict[str, Any]:
    """Return the JSON shape saved to disk."""
    owner, name = repo["full_name"].split("/", 1)
    evidence = set(repo.get("matchedEvidence", set()))
    return {
        "name": name,
        "owner": owner,
        "description": repo.get("description") or "No description",
        "url": repo.get("html_url"),
        "primaryLanguage": repo.get("language") or "N/A",
        "stargazerCount": repo.get("stargazers_count", 0),
        "forkCount": repo.get("forks_count", 0),
        "isArchived": repo.get("archived", False),
        "isFork": repo.get("fork", False),
        "pushedAt": repo.get("pushed_at"),
        "evidenceScore": evidence_score(evidence),
        "topics": sorted(repo.get("topics", [])),
        "matchedEvidence": sorted(evidence),
        "matchedPaths": sorted(repo.get("matchedPaths", [])),
        "matchedQueries": sorted(repo.get("matchedQueries", [])),
    }


def passes_filter(repo: dict[str, Any]) -> bool:
    """Return True if a repo has raw axios and NestJS evidence."""
    evidence = set(repo.get("matchedEvidence", set()))
    has_axios = bool(evidence & AXIOS_EVIDENCE)
    has_nestjs = bool(evidence & NESTJS_EVIDENCE)
    return has_axios and has_nestjs and evidence_score(evidence) >= MIN_EVIDENCE_SCORE


def passes_project_filter(repo: dict[str, Any]) -> bool:
    """Return True for application/project repos, not templates or libraries."""
    return project_exclusion_reason(repo) is None


def main() -> None:
    token = (os.environ.get("GITHUB_TOKEN") or "").strip()
    if not token:
        print("Error: set the GITHUB_TOKEN environment variable.", file=sys.stderr)
        sys.exit(1)

    repos_by_name: dict[str, dict[str, Any]] = {}
    hit_rate_limit = False

    for entry in SEARCH_QUERIES:
        query = entry["query"]
        search_type = entry["type"]
        evidence = set(entry["evidence"])
        print(f"Searching {search_type} [{', '.join(sorted(evidence))}]: {query}")
        try:
            items = (
                search_code(token, query)
                if search_type == "CODE"
                else search_repositories(token, query)
            )
        except RuntimeError as exc:
            if "HTTP 401" in str(exc):
                print(f"Error: GitHub rejected GITHUB_TOKEN: {exc}", file=sys.stderr)
                sys.exit(1)
            if "HTTP 403" in str(exc) and "rate limit" in str(exc).lower():
                hit_rate_limit = True
                print(f"  {exc}", file=sys.stderr)
                break
            print(f"  {exc}", file=sys.stderr)
            continue

        print(f"  returnedItems: {len(items)}")
        for item in items:
            repo = item["repository"] if search_type == "CODE" else item
            name_with_owner = repo["full_name"]
            saved = repos_by_name.setdefault(
                name_with_owner,
                {
                    **repo,
                    "matchedPaths": set(),
                    "matchedQueries": set(),
                    "matchedEvidence": set(),
                },
            )
            if search_type == "CODE" and item.get("path"):
                saved["matchedPaths"].add(item["path"])
            saved["matchedQueries"].add(query)
            saved["matchedEvidence"].update(evidence)

        time.sleep(PAUSE_SECONDS)

    confirmed = {
        name: repo
        for name, repo in repos_by_name.items()
        if passes_filter(repo)
    }
    skipped = len(repos_by_name) - len(confirmed)
    print(f"\n{skipped} repositories skipped (missing axios or NestJS evidence).")
    print(f"Fetching metadata for {len(confirmed)} candidate repositories...")

    full_repos: list[dict[str, Any]] = []
    for name_with_owner, partial_repo in confirmed.items():
        try:
            full_repo = fetch_repository(token, name_with_owner)
        except RuntimeError as exc:
            if "HTTP 403" in str(exc) and "rate limit" in str(exc).lower():
                hit_rate_limit = True
                print(f"  Rate limit hit while fetching repository metadata: {exc}", file=sys.stderr)
                break
            print(f"  Could not fetch metadata for {name_with_owner}: {exc}", file=sys.stderr)
            continue

        full_repo["matchedPaths"] = partial_repo["matchedPaths"]
        full_repo["matchedQueries"] = partial_repo["matchedQueries"]
        full_repo["matchedEvidence"] = partial_repo["matchedEvidence"]
        full_repos.append(full_repo)
        time.sleep(0.2)

    repositories = []
    excluded_projects = 0
    for repo in full_repos:
        if repo.get("stargazers_count", 0) < MIN_STARS:
            continue
        if repo.get("fork", False) or repo.get("archived", False):
            continue
        exclusion_reason = project_exclusion_reason(repo)
        if exclusion_reason:
            excluded_projects += 1
            print(f"  Excluding {repo['full_name']}: {exclusion_reason}")
            continue
        repositories.append(normalize_repository(repo))

    repositories.sort(
        key=lambda item: (item["evidenceScore"], item["stargazerCount"]),
        reverse=True,
    )
    print(f"\n{excluded_projects} repositories excluded as boilerplate/example/library repos.")

    if hit_rate_limit and not repositories:
        print(
            "\nGitHub rate-limited the run before any qualifying repositories were saved. "
            f"Keeping existing {OUTPUT_FILE} unchanged.",
            file=sys.stderr,
        )
        sys.exit(1)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as file:
        json.dump(repositories, file, indent=2)

    print(f"\nSaved {len(repositories)} repositories to {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
