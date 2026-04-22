"""Reading CodeQL CSV output into protocol-agnostic ``ConnectorEdge`` objects.

The Axios query (``dataflow6.ql``) emits columns:

    source | callerService | configKey | sink | resolvedEndpoint | httpMethod

Future gRPC and Redis queries are expected to emit the same column shape, with
``httpMethod`` carrying the port-type verb (HTTP method, gRPC ``/pkg.Svc/M``,
Redis command, etc.).  Downstream stages only require ``callerService``,
``resolvedEndpoint`` (second-to-last), and ``httpMethod``; the rest is
preserved for debugging.
"""

from __future__ import annotations

import csv
from typing import Dict, Iterator, List, Optional

from .env_resolver import resolve_url_placeholders
from .models import ConnectorEdge


def iter_resolved_edges(
    csv_path: str, env_vars: Dict[str, str]
) -> Iterator[ConnectorEdge]:
    """Stream ``ConnectorEdge`` values from a CodeQL CSV, resolving env placeholders.

    Rows are skipped when:
      - they have fewer than 4 columns (same guard as the original script);
      - ``resolvedEndpoint`` is empty;
      - the URL contains no ``{*_URL}`` placeholders; or
      - any referenced env var is missing from ``env_vars``.

    The caller is responsible for deduplication (see ``ConnectorEdge.dedup_key``).
    """
    with open(csv_path, mode="r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        if header is None:
            return
        print(f"DEBUG: Header columns: {header}")
        print(f"DEBUG: Loaded env vars: {list(env_vars.keys())}")

        try:
            caller_idx = header.index("callerService")
            http_method_idx = header.index("httpMethod")
        except ValueError as e:
            print(f"Error: Missing required column in CSV header - {e}")
            return

        for row in reader:
            if len(row) < 4:
                continue
            call_info = row[0]
            caller_service = row[caller_idx]
            http_method = row[http_method_idx]
            raw_url = row[-2]
            if not raw_url:
                continue

            resolution = resolve_url_placeholders(raw_url, env_vars)
            if resolution is None:
                continue
            resolved_url, placeholders = resolution

            yield ConnectorEdge(
                location=call_info,
                caller_service=caller_service,
                env_vars=tuple(placeholders),
                resolved_url=resolved_url,
                method=http_method,
            )


def read_header_columns(csv_path: str) -> Optional[List[str]]:
    """Return the CSV header row, or ``None`` if the file is missing/empty."""
    with open(csv_path, mode="r", encoding="utf-8") as f:
        reader = csv.reader(f)
        return next(reader, None)
