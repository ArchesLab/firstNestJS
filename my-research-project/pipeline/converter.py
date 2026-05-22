"""
converter.py - thin orchestrator that wires the pipeline stages together.

WHY A TINY ENTRY POINT:
  Each of the four pipeline stages (parse -> normalise -> dedupe ->
  render) lives in its own module. This file is deliberately minimal -
  it exists only to describe the top-level control flow. That means:
    - Swapping any stage out is a one-import change here.
    - The file reads top-to-bottom the same way the ROSDiscover paper
      reads (Component Model Recovery -> Composition -> Checking).

USAGE:
  python -m my-research-project.pipeline.converter \
      --input tests/final_result.txt \
      --output ../diagram.puml

  The defaults mirror the old `converter.py` behaviour, so existing
  build scripts keep working without changes.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import replace
from pathlib import Path

from . import normalizers, parser, plantuml_renderer
from .models import ConnectorRecord


# Default locations match the legacy converter so downstream scripts
# (benchmark.ps1, CI) keep working. Resolved relative to this file so
# the tool can be run from any working directory.
_HERE = Path(__file__).resolve().parent
DEFAULT_INPUT = _HERE.parent / "tests" / "final_result.txt"
DEFAULT_OUTPUT = _HERE.parent.parent / "diagram.puml"


def _build_arg_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description=(
            "Recover the microservice architecture from CodeQL results and "
            "render it as PlantUML."
        ),
    )
    p.add_argument(
        "--input", "-i", type=Path, default=DEFAULT_INPUT,
        help="CodeQL pipe-separated result file (default: tests/final_result.txt)",
    )
    p.add_argument(
        "--output", "-o", type=Path, default=DEFAULT_OUTPUT,
        help="Destination PlantUML file (default: diagram.puml at repo root)",
    )
    p.add_argument(
        "--no-connect-ports", action="store_true", default=False,
        help=(
            "Show every port individually instead of combining ports that "
            "share the same label. When set, each record gets its own "
            "portin/portout and edges connect portout to portin."
        ),
    )
    p.add_argument(
        "--service-view", action="store_true", default=False,
        help=(
            "Aggregate connector facts by caller, target, and protocol so "
            "the output shows service-to-service communication rather than "
            "one edge per recovered endpoint/key."
        ),
    )
    return p


def run(input_path: Path, output_path: Path,
        connect_ports: bool = True,
        service_view: bool = False) -> None:
    """Execute the full pipeline - the only non-trivial function in this
    file.

    ORDER MATTERS:
      1. Parse. Raw text -> typed records, drop unknown protocols.
      2. Normalise. Protocol-specific cleanup (strip placeholders, etc.).
      3. Render. Emit PlantUML.
    We do NOT dedupe here - the parser already deduplicates at set-level
    precision, which is the right granularity for "one connector per
    architectural fact".
    """
    raw_records = parser.parse_file(input_path)
    if not raw_records:
        print(f"No connector records found in {input_path}.")
        return

    cleaned = [normalizers.normalise(r) for r in raw_records]
    if service_view:
        cleaned = _aggregate_service_view(cleaned)

    plantuml = plantuml_renderer.render(cleaned, connect_ports=connect_ports)

    output_path.write_text(plantuml, encoding="utf-8")
    print(
        f"Wrote {len(cleaned)} connector(s) to {output_path} "
        f"(protocols: {sorted({r.protocol for r in cleaned})})"
    )


def _aggregate_service_view(records: list[ConnectorRecord]) -> list[ConnectorRecord]:
    """Collapse endpoint-level facts into service-level communication edges."""
    grouped: dict[tuple[str, str, str], list[ConnectorRecord]] = defaultdict(list)
    for record in records:
        grouped[(record.protocol, record.caller_service, record.target_service)].append(record)

    aggregated: list[ConnectorRecord] = []
    for (protocol, caller, target), group in grouped.items():
        operations = sorted({r.operation.upper() for r in group})
        endpoint_count = len({r.endpoint for r in group})
        config_keys = sorted({r.config_key for r in group if r.config_key})
        first = sorted(group, key=lambda r: (r.operation, r.endpoint, r.location))[0]

        if protocol == "redis":
            operation = "Redis"
            endpoint = f"{endpoint_count} key pattern(s); commands: {', '.join(operations)}"
        elif protocol == "grpc":
            operation = ", ".join(operations)
            endpoint = f"{endpoint_count} RPC endpoint(s)"
        elif protocol == "rest":
            operation = ", ".join(operations)
            endpoint = f"{endpoint_count} HTTP endpoint(s)"
        else:
            operation = protocol.upper()
            endpoint = f"{endpoint_count} endpoint(s); operations: {', '.join(operations)}"

        aggregated.append(
            replace(
                first,
                operation=operation,
                endpoint=endpoint,
                config_key=", ".join(config_keys),
            )
        )

    return sorted(
        aggregated,
        key=lambda r: (r.protocol, r.caller_service, r.target_service, r.endpoint),
    )


def main() -> None:
    args = _build_arg_parser().parse_args()
    run(args.input, args.output,
        connect_ports=not args.no_connect_ports,
        service_view=args.service_view)


if __name__ == "__main__":
    main()
