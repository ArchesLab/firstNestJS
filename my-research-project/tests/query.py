"""Entry point: CodeQL CSV → resolved connector edges → ``final_result.txt``.

Thin wrapper over the ``pipeline`` package.  Semantics-preserving with the
prior single-file implementation: same column widths, same debug messages,
same dedup key, same ``.env`` resolution rules.
"""

from __future__ import annotations

import os
import sys
from typing import List

# Allow running as ``python tests/query.py`` without installing the package.
_PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PROJECT_ROOT not in sys.path:
    sys.path.insert(0, _PROJECT_ROOT)

from pipeline.csv_parser import iter_resolved_edges
from pipeline.env_resolver import load_env_files
from pipeline.formatter import HEADER_LINE, SEPARATOR, format_edge, iter_unique_edges


# Keep this list as it was — preserved verbatim from the pre-refactor script.
DEFAULT_ENV_LOCATIONS: List[str] = [
    r"C:\Users\mary\Clubs\Research\simple-app\events\.env",
    r"C:\Users\mary\Clubs\Research\simple-app\users\.env",
    r"C:\Users\mary\Clubs\Research\simple-app\notifications\.env",
    r"C:\Users\mary\Clubs\Research\simple-app\clubs\.env",
]

DEFAULT_CSV_PATH = r"C:\Users\mary\Clubs\Research\simple-app\my-research-project\codeql_results.csv"


def process_codeql_csv(csv_path: str, env_vars: dict, output_path: str) -> None:
    if not os.path.exists(csv_path):
        print(f"Error: CSV file {csv_path} not found.")
        return

    with open(output_path, mode="w", encoding="utf-8") as out:
        print("\n" + HEADER_LINE)
        print(SEPARATOR)
        out.write(HEADER_LINE + "\n")
        out.write(SEPARATOR + "\n")

        for edge in iter_unique_edges(iter_resolved_edges(csv_path, env_vars)):
            line = format_edge(edge)
            print(line)
            out.write(line + "\n")


if __name__ == "__main__":
    master_env = load_env_files(DEFAULT_ENV_LOCATIONS)
    output_path = os.path.join(os.path.dirname(__file__), "final_result.txt")
    process_codeql_csv(DEFAULT_CSV_PATH, master_env, output_path)
