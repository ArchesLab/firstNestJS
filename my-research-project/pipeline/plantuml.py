"""Render a set of ``ConnectorEdge`` objects as a PlantUML component diagram.

Output is byte-compatible with the pre-refactor ``converter.generate_plantuml``
for the existing microservice components.  The component list is exposed as a
constant so future callers (gRPC, Redis) can provide their own.
"""

from __future__ import annotations

from typing import Dict, Iterable, List, Sequence

from .models import ConnectorEdge
from .text_parser import infer_target_service, split_url

# Preserved from the pre-refactor ``converter.generate_plantuml`` — same
# components, same ordering, same rendering.
DEFAULT_COMPONENTS: Sequence[str] = (
    "gateway",
    "auth",
    "users",
    "clubs",
    "events",
    "notifications",
)


def _edge_to_connection(edge: ConnectorEdge) -> Dict[str, str]:
    """Project a ``ConnectorEdge`` to the ``caller/target/path/method`` shape
    the renderer consumes.  Returns an empty dict for URLs that cannot be
    split (the caller filters these out)."""
    parts = split_url(edge.resolved_url)
    if parts is None:
        return {}
    _base, path = parts
    target = infer_target_service(edge.resolved_url) or ""
    return {
        "caller": edge.caller_service,
        "target": target,
        "path": path,
        "method": edge.method,
    }


def render(
    edges: Iterable[ConnectorEdge],
    components: Sequence[str] = DEFAULT_COMPONENTS,
) -> str:
    """Render the component/port diagram. Preserves byte-compatible output."""
    connections = [c for c in (_edge_to_connection(e) for e in edges) if c]
    connections = [c for c in connections if c["caller"] in components and c["target"] in components]
    unique = _dedupe_connections(connections)

    out: List[str] = []
    out.append("@startuml\n")
    out.append("!theme plain\n")
    out.append("left to right direction\n")
    out.append("skinparam componentStyle uml2\n")
    out.append("skinparam nodesep 20\n")
    out.append("skinparam ranksep 150\n\n")

    out.append("' Force all components to stay on the same horizontal rank\n")
    out.append("together {\n")
    for comp in components:
        out.append(f"  component [{comp}] as {comp}\n")
    out.append("}\n\n")

    out.append("' Maintain the horizontal sequence\n")
    for i in range(len(components) - 1):
        out.append(f"{components[i]} -[hidden]r- {components[i + 1]}\n")
    out.append("\n")

    out.append("' --- Port Definitions ---\n\n")
    ports: Dict[str, str] = {}
    for comp in components:
        if any(c["target"] == comp for c in unique):
            port_alias = f"{comp}_port"
            ports[comp] = port_alias
            out.append(f"component {comp} {{\n")
            out.append(f'    portin "/{comp}" as {port_alias}\n')
            out.append("}\n\n")

    out.append("' --- Connections ---\n\n")
    for c in unique:
        target_port_alias = ports.get(c["target"])
        if target_port_alias:
            out.append(
                f'{c["caller"]} --> {target_port_alias} : "{c["method"]} {c["path"]}"\n'
            )

    out.append("@enduml\n")
    return "".join(out)


def _dedupe_connections(connections: List[Dict[str, str]]) -> List[Dict[str, str]]:
    """Deduplicate via the set-of-tuple-items method from the original.

    Order is hash-determined — identical to pre-refactor behaviour.
    """
    return [dict(t) for t in {tuple(d.items()) for d in connections}]
