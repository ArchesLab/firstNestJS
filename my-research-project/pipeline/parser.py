"""
parser.py - reads CodeQL's pipe-separated output into `ConnectorRecord`s.

WHY A DEDICATED PARSER MODULE:
  The old converter parsed and rendered in the same function. Splitting
  parsing out means:
    - We can swap in a different CodeQL output format (JSON, CSV, BQRS)
      by replacing this one file, not rewriting the pipeline.
    - The parser has no opinions about WHAT to do with records - it just
      shepherds them from text into typed objects.
"""

from pathlib import Path
from typing import List

from .models import ConnectorRecord, normalise_protocol


# Columns as emitted by `all_connectors.ql`. Kept in ONE place so a schema
# change is a one-line edit here.
EXPECTED_COLUMNS = (
    "protocol",
    "callerService",
    "operation",
    "targetService",
    "endpoint",
    "configKey",
    "location",
)


def _is_header_or_separator(line: str) -> bool:
    """Skip CodeQL's table header and the `----` separator row.

    WHY WE MATCH BOTH:
      CodeQL's decoded output for `@kind table` prints the column names,
      then a line of dashes, then data. The old converter hard-coded
      "skip the first two lines" (`lines[2:]`). That breaks if CodeQL
      ever emits a blank line or extra metadata. Content-based skipping
      is more robust.
    """
    stripped = line.strip()
    if not stripped:
        return True
    # Header row: contains "callerService" or "protocol" as a literal word.
    if "callerService" in stripped or stripped.startswith("protocol"):
        return True
    # Separator row: made entirely of dashes / pipes / spaces.
    if set(stripped) <= set("-| "):
        return True
    return False


def parse_line(line: str) -> ConnectorRecord | None:
    """Turn one pipe-separated row into a `ConnectorRecord`, or `None`
    when the row is malformed or uses an unknown protocol."""
    parts = [p.strip() for p in line.split("|")]
    if len(parts) < len(EXPECTED_COLUMNS):
        return None

    protocol = normalise_protocol(parts[0])
    if protocol is None:
        # Unknown protocol - silently skip rather than crash so we can
        # extend CodeQL independently of the Python pipeline during dev.
        return None

    return ConnectorRecord(
        protocol=protocol,
        caller_service=parts[1],
        operation=parts[2],
        target_service=parts[3],
        endpoint=parts[4],
        config_key=parts[5],
        location=parts[6],
    )


def parse_file(path: Path) -> List[ConnectorRecord]:
    """Read every connector record from a CodeQL result file.

    Returns a DEDUPLICATED list: two identical rows collapse into one.
    WHY DEDUPLICATE HERE RATHER THAN IN THE RENDERER:
      A connector recovered twice is still ONE architectural connector.
      Removing duplicates at parse time keeps the diagram clean and lets
      the renderer assume each record is unique.
    """
    with path.open("r", encoding="utf-8") as fp:
        records: set[ConnectorRecord] = set()
        for raw_line in fp:
            if _is_header_or_separator(raw_line):
                continue
            parsed = parse_line(raw_line)
            if parsed is not None:
                records.add(parsed)
    return list(records)
