"""Parse the pipe-delimited ``final_result.txt`` back into connector edges.

Used by ``converter.py`` when the PlantUML renderer operates on the
post-processed text report rather than the raw CodeQL CSV.  Behaviour is
identical to the original ``parse_line`` in ``converter.py``.
"""

from __future__ import annotations

import re
from typing import Iterable, Iterator, List, Optional

from .models import ConnectorEdge

# Split a resolved URL ``{base}path`` into ``(base, path)``.
BASE_URL_RE = re.compile(r"\{(.*?)\}(.*)")


def parse_result_line(line: str) -> Optional[ConnectorEdge]:
    """Parse one pipe-delimited ``final_result.txt`` line.

    Returns ``None`` for malformed lines (fewer than five pipe-separated
    parts) — identical to the original ``parse_line``.  Env-var and location
    fields are preserved verbatim from the report so round-tripping is
    lossless for the columns the downstream consumers actually use.
    """
    parts = [p.strip() for p in line.split("|")]
    if len(parts) < 5:
        return None
    location = parts[0]
    caller_service = parts[1]
    env_vars_raw = parts[2]
    resolved_url = parts[3]
    http_method = parts[4]

    env_vars = tuple(v.strip() for v in env_vars_raw.split(",")) if env_vars_raw else ()
    return ConnectorEdge(
        location=location,
        caller_service=caller_service,
        env_vars=env_vars,
        resolved_url=resolved_url,
        method=http_method,
    )


def parse_result_lines(lines: Iterable[str]) -> Iterator[ConnectorEdge]:
    """Parse many lines, yielding non-empty, well-formed edges."""
    for line in lines:
        if not line.strip():
            continue
        edge = parse_result_line(line)
        if edge is not None:
            yield edge


def split_url(resolved_url: str) -> Optional[tuple]:
    """Split ``{base}path`` into ``(base, path)``, or ``None`` if unmatched."""
    m = BASE_URL_RE.search(resolved_url)
    if not m:
        return None
    return m.groups()


def infer_target_service(resolved_url: str) -> Optional[str]:
    """Infer the target service name from the first URL path segment."""
    parts = split_url(resolved_url)
    if parts is None:
        return None
    _base, path = parts
    segments = path.strip("/").split("/")
    return segments[0] if segments else ""
