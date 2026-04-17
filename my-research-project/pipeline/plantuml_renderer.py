"""
plantuml_renderer.py - turns normalised records into a PlantUML diagram.

WHY SEPARATE FROM THE PARSER / NORMALIZER:
  The previous single-file converter mixed "how do I parse?" with "how
  do I draw?". Splitting these concerns means:
    - The renderer knows NOTHING about the input format, so swapping
      PlantUML for Mermaid / DOT is a one-file change.
    - The parser has no opinions about display, so a CI rule checker
      can consume the records directly without touching the renderer.

RENDERING STRATEGY:
  We preserve the original PlantUML style (horizontal layout, typed
  ports, labelled edges) but:
    - Add a `redis` component when at least one Redis record exists.
    - Add gRPC components dynamically when the recovered target matches a
      workspace folder OR is an external `grpc:X` label.
    - Use edge STYLE (solid / dashed / dotted) to visually distinguish
      protocols, matching the "mapping table" convention the paper uses
      to distinguish topics, services and actions.
"""

from collections import defaultdict
from typing import Dict, Iterable, List, Set

from .models import ConnectorRecord


# The six workspace services from the monorepo. We keep the order stable
# so diffs between runs stay minimal. Static list mirrors the
# `knownService/1` predicate in ServiceIdentification.qll - a change here
# should mirror a change there.
KNOWN_SERVICES: List[str] = [
    "gateway", "auth", "users", "clubs", "events", "notifications",
]

# Visual vocabulary per protocol. Edges use PlantUML arrow modifiers:
#   -->   : solid (REST - the default, most common)
#   -[dashed]->   : dashed (gRPC - emphasises RPC semantics)
#   -[dotted]->   : dotted (Redis - treats Redis as a shared resource)
# Keeping the mapping in ONE dictionary means new protocols can be added
# without touching the rendering loop.
EDGE_STYLE: Dict[str, str] = {
    "rest": "-->",
    "grpc": "-[dashed]->",
    "redis": "-[dotted]->",
}


def _collect_components(records: Iterable[ConnectorRecord]) -> List[str]:
    """Assemble the full component list: workspace services + extras
    introduced by non-REST protocols (`redis`, `grpc:Foo`, ...).

    WHY COMPONENTS COME FROM DATA:
      Hard-coding only the six microservice folders (as the old
      converter did) hides the existence of Redis / gRPC servers in the
      diagram. Pulling components from the recovered records ensures the
      architecture view matches what the code actually does.
    """
    extras: Set[str] = set()
    for r in records:
        for endpoint in (r.caller_service, r.target_service):
            if endpoint and endpoint not in KNOWN_SERVICES \
                    and endpoint != "unknown-service":
                extras.add(endpoint)
    # Stable order: known services first, extras alphabetical after.
    return KNOWN_SERVICES + sorted(extras)


def _port_label(record: ConnectorRecord) -> str:
    """Port label for the target component.

    WHY PROTOCOL-DEPENDENT LABELS:
      A REST port is a URL path; a gRPC port is a `/Service/Method`; a
      Redis port is a key namespace. Keeping them visually distinct in
      the diagram helps a reader tell at a glance what kind of
      interaction is modelled.
    """
    if record.protocol == "rest":
        # The first path segment doubles as the port name (matches the
        # original converter's behaviour).
        segments = [s for s in record.endpoint.split("/") if s]
        return "/" + segments[0] if segments else "/"
    if record.protocol == "grpc":
        # Use the full method path; each gRPC method is a distinct port.
        return record.endpoint
    if record.protocol == "redis":
        # All Redis calls share a single "commands" port for the Redis
        # component - individual keys go on the edge label instead.
        return "commands"
    return record.endpoint


def _edge_label(record: ConnectorRecord) -> str:
    """Label shown on the arrow between caller and target component."""
    if record.protocol == "rest":
        return f"{record.operation} {record.endpoint}"
    if record.protocol == "grpc":
        # gRPC method name already contains semantics; endpoint is
        # structural.
        return f"gRPC {record.operation}"
    if record.protocol == "redis":
        return f"{record.operation} {record.endpoint}"
    return record.operation


def render(records: List[ConnectorRecord]) -> str:
    """Produce a PlantUML document from a list of connector records."""
    components = _collect_components(records)

    # Port slot per component - deduplicated so we don't emit repeat
    # `portin` declarations.
    component_ports: Dict[str, Set[str]] = defaultdict(set)
    for r in records:
        if r.target_service in components:
            component_ports[r.target_service].add(_port_label(r))

    lines: List[str] = []
    lines.append("@startuml")
    lines.append("!theme plain")
    lines.append("left to right direction")
    lines.append("skinparam componentStyle uml2")
    lines.append("skinparam nodesep 20")
    lines.append("skinparam ranksep 150")
    lines.append("")

    # Step 1: declare every component up-front so PlantUML lays them out
    # on a single horizontal rank. Same layout trick the legacy renderer
    # used - preserved so visual diffs stay small for existing users.
    lines.append("together {")
    for comp in components:
        lines.append(f"  component [{comp}] as {_alias(comp)}")
    lines.append("}")
    lines.append("")

    # Step 2: hidden ordering edges to keep the horizontal sequence.
    for a, b in zip(components, components[1:]):
        lines.append(f"{_alias(a)} -[hidden]r- {_alias(b)}")
    lines.append("")

    # Step 3: emit ports for targets that actually receive calls.
    lines.append("' --- Port definitions ---")
    lines.append("")
    for comp in components:
        if not component_ports.get(comp):
            continue
        lines.append(f"component {_alias(comp)} {{")
        for port in sorted(component_ports[comp]):
            lines.append(f'    portin "{port}" as {_port_alias(comp, port)}')
        lines.append("}")
        lines.append("")

    # Step 4: emit connections with protocol-aware edge styling.
    lines.append("' --- Connections ---")
    lines.append("")
    for r in sorted(records, key=_record_sort_key):
        if r.caller_service not in components:
            continue
        if r.target_service not in components:
            continue
        port_alias = _port_alias(r.target_service, _port_label(r))
        arrow = EDGE_STYLE.get(r.protocol, "-->")
        lines.append(
            f'{_alias(r.caller_service)} {arrow} {port_alias} '
            f': "{_edge_label(r)}"'
        )

    lines.append("@enduml")
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _alias(component: str) -> str:
    """PlantUML aliases cannot contain `:` or `-` reliably, so we
    sanitise. This is the one piece of glue that lets `grpc:UserService`
    and `unknown-service` still appear in diagrams."""
    return component.replace(":", "_").replace("-", "_")


def _port_alias(component: str, port: str) -> str:
    safe_port = "".join(c if c.isalnum() else "_" for c in port).strip("_")
    return f"{_alias(component)}_{safe_port or 'port'}"


def _record_sort_key(r: ConnectorRecord) -> tuple:
    """Deterministic ordering for a stable diagram between runs."""
    return (r.protocol, r.caller_service, r.target_service,
            r.operation, r.endpoint)
