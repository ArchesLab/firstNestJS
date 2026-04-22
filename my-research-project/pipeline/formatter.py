"""Pipe-delimited text formatter for the human-readable ``final_result.txt``.

Output format is byte-compatible with the original ``tests/query.py`` so
downstream tools (``converter.py`` and any external parsers) keep working.
Column widths and separators are frozen as module constants.
"""

from __future__ import annotations

from typing import Iterable, Iterator

from .models import ConnectorEdge

# Column widths — frozen to match the pre-refactor output exactly.
LOCATION_TRUNCATE = 28
LOCATION_WIDTH = 30
CALLER_WIDTH = 15
ENV_WIDTH = 35
URL_WIDTH = 40
SEPARATOR = "-" * 120

HEADER_LINE = (
    f"{'Location':<{LOCATION_WIDTH}} | "
    f"{'Caller Service':<{CALLER_WIDTH}} | "
    f"{'Extracted Env Vars':<{ENV_WIDTH}} | "
    f"{'Resolved URL':<{URL_WIDTH}} | "
    f"{'HTTP Method'}"
)


def format_edge(edge: ConnectorEdge) -> str:
    """Render one edge as a single pipe-delimited line."""
    return (
        f"{edge.location[:LOCATION_TRUNCATE]:<{LOCATION_WIDTH}} | "
        f"{edge.caller_service:<{CALLER_WIDTH}} | "
        f"{', '.join(edge.env_vars):<{ENV_WIDTH}} | "
        f"{edge.resolved_url:<{URL_WIDTH}} | "
        f"{edge.method}"
    )


def iter_unique_edges(edges: Iterable[ConnectorEdge]) -> Iterator[ConnectorEdge]:
    """Yield edges in input order, skipping those whose ``dedup_key`` was seen.

    Dedup key is ``(caller_service, env_vars, method)`` — same as the original
    script.  The first occurrence of each key is kept.
    """
    seen = set()
    for edge in edges:
        key = edge.dedup_key
        if key in seen:
            continue
        seen.add(key)
        yield edge
