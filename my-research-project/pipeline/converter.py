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
from pathlib import Path

from . import normalizers, parser, plantuml_renderer


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
    return p


def run(input_path: Path, output_path: Path) -> None:
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
    plantuml = plantuml_renderer.render(cleaned)

    output_path.write_text(plantuml, encoding="utf-8")
    print(
        f"Wrote {len(cleaned)} connector(s) to {output_path} "
        f"(protocols: {sorted({r.protocol for r in cleaned})})"
    )


def main() -> None:
    args = _build_arg_parser().parse_args()
    run(args.input, args.output)


if __name__ == "__main__":
    main()
