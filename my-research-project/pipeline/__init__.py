# Package marker for the connector-recovery pipeline.
#
# WHY A PACKAGE AT ALL:
#   The original `converter.py` bundled parsing, normalisation and
#   rendering into a single 116-line file. Adding two more protocols
#   (gRPC, Redis) with protocol-specific post-processing would turn it
#   into a ball of conditionals. A package makes the pipeline stages
#   explicit and unit-testable.
#
# WHAT LIVES WHERE:
#   models.py           - plain data classes the rest of the code shares
#   parser.py           - reads CodeQL's pipe-separated output
#   normalizers.py      - per-protocol cleanup (endpoint canonicalisation)
#   plantuml_renderer.py- turns records into the final `.puml` diagram
#   converter.py        - the thin orchestrator: parse -> normalise -> render
