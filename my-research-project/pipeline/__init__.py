"""Protocol-agnostic core of the CPC extraction pipeline.

Modules
-------
- models:       dataclasses representing CPC edges produced by the analysis.
- env_resolver: load and merge .env files; substitute ``{VAR}`` placeholders.
- csv_parser:   read CodeQL CSV output into column-keyed dicts.
- formatter:    render a stream of edges as the pipe-delimited human report.
- plantuml:     render a stream of edges as a PlantUML component diagram.

The Axios, gRPC, and Redis CodeQL queries all emit a CSV with the same shape
(``callerService``, ``configKey``, ``resolvedEndpoint``, ``httpMethod`` /
``portType``, ...) so the downstream Python stages are shared across protocols.
"""
