"""Entry point: ``final_result.txt`` → ``diagram.puml``.

Thin wrapper over the ``pipeline`` package.  Semantics-preserving with the
prior single-file implementation: same hardcoded components list, same
dedup-by-item-tuple method, byte-compatible PlantUML output.
"""

from __future__ import annotations

import os
import sys

_PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
if _PROJECT_ROOT not in sys.path:
    sys.path.insert(0, _PROJECT_ROOT)

from pipeline.plantuml import render
from pipeline.text_parser import parse_result_lines


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
INPUT_FILE_PATH = os.path.join(SCRIPT_DIR, "tests", "final_result.txt")
OUTPUT_FILE_PATH = "diagram.puml"


def main() -> None:
    try:
        with open(INPUT_FILE_PATH, "r") as f:
            # Skip the two header lines (title row + separator) emitted by
            # ``tests/query.py``.
            lines = f.readlines()[2:]
    except FileNotFoundError:
        print(f"Error: {INPUT_FILE_PATH} not found.")
        return

    edges = list(parse_result_lines(lines))
    plantuml_output = render(edges)
    with open(OUTPUT_FILE_PATH, "w") as f:
        f.write(plantuml_output)
    print("Successfully generated diagram.puml")


if __name__ == "__main__":
    main()
