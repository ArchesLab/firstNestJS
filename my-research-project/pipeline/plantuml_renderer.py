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


# ---------------------------------------------------------------------------
# Service name discovery
# ---------------------------------------------------------------------------
# KNOWN_SERVICES has been removed — the renderer now derives all component
# names directly from the caller_service / target_service fields in the
# ConnectorRecords.  This makes the pipeline reusable across repositories
# without editing a hard-coded list.
# ---------------------------------------------------------------------------

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
    """Assemble the full component list purely from connector records.

    Every distinct caller_service and target_service (except the sentinel
    'unknown-service') becomes a component.  Sorted alphabetically so diffs
    between runs stay minimal regardless of which repo is analysed.
    """
    components: Set[str] = set()
    for r in records:
        for endpoint in (r.caller_service, r.target_service):
            if endpoint and endpoint != "unknown-service":
                components.add(endpoint)
    return sorted(components)


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


def render(records: List[ConnectorRecord],
           connect_ports: bool = True) -> str:
    """Produce a PlantUML document from a list of connector records.

    Args:
        records: Normalised connector records.
        connect_ports: If True (default), combine ports that share the
            same label on each component and draw edges from the caller
            component directly to the shared portin.  If False, show
            every port individually with separate portin/portout per
            record and draw edges from caller portout to target portin.
    """
    if connect_ports:
        return _render_combined(records)
    return _render_individual(records)


def _render_combined(records: List[ConnectorRecord]) -> str:
    """Combined-ports mode: deduplicate port labels, edges from
    component → shared portin."""
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


def _render_individual(records: List[ConnectorRecord]) -> str:
    """Individual-ports mode: every record gets its own portin and
    portout; edges go from caller portout → target portin.

    Port labels use the full endpoint path for maximum architectural
    accuracy.  No layout hints are emitted so PlantUML's engine can
    calculate the shortest path between components.
    """
    components = _collect_components(records)
    prefix_map = _compute_short_prefixes(components)

    # Per-component running counters for portin / portout.
    portin_counters: Dict[str, int] = defaultdict(int)
    portout_counters: Dict[str, int] = defaultdict(int)

    # Per-component ordered lists of (label, alias) for ports.
    component_portins: Dict[str, List[tuple]] = defaultdict(list)
    component_portouts: Dict[str, List[tuple]] = defaultdict(list)

    # For each valid record, store the assigned port aliases so we can
    # emit the right edge later.
    record_ports: List[tuple] = []   # (portout_alias, portin_alias, record)

    for r in sorted(records, key=_record_sort_key):
        if r.caller_service not in components:
            continue
        if r.target_service not in components:
            continue

        # Assign a portout on the caller.
        portout_counters[r.caller_service] += 1
        out_idx = portout_counters[r.caller_service]
        caller_pfx = _short_prefix(r.caller_service, prefix_map)
        portout_alias = f"{caller_pfx}_out{out_idx}"
        portout_label = f"out{out_idx}"
        component_portouts[r.caller_service].append(
            (portout_label, portout_alias)
        )

        # Assign a portin on the target — full endpoint path.
        portin_counters[r.target_service] += 1
        in_idx = portin_counters[r.target_service]
        target_pfx = _short_prefix(r.target_service, prefix_map)
        portin_alias = f"{target_pfx}_p{in_idx}"
        portin_label = r.endpoint
        component_portins[r.target_service].append(
            (portin_label, portin_alias)
        )

        record_ports.append((portout_alias, portin_alias, r))

    lines: List[str] = []
    lines.append("@startuml")

    # Emit component blocks with their ports.  No together/hidden
    # edges — let PlantUML's auto-layout determine placement.
    for comp in components:
        portins = component_portins.get(comp, [])
        portouts = component_portouts.get(comp, [])
        if not portins and not portouts:
            continue
        comp_name = comp.title()
        lines.append(f"component {comp_name} {{")
        for label, alias in portins:
            lines.append(f'  portin "{label}" as {alias}')
        for label, alias in portouts:
            lines.append(f'  portout "{label}" as {alias}')
        lines.append("}")
        lines.append("")

    # Emit connections from portout → portin.
    for portout_alias, portin_alias, r in record_ports:
        arrow = EDGE_STYLE.get(r.protocol, "-->")
        lines.append(
            f'{portout_alias} {arrow} {portin_alias} '
            f': {r.operation.upper()}'
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


def _compute_short_prefixes(components: List[str]) -> Dict[str, str]:
    """Return a map component -> unique short prefix for port aliases.

    We start with the first character and lengthen the prefix until every
    component has a distinct value.  This avoids collisions when two
    services share an initial letter (e.g. 'users' and 'uploads').
    """
    aliases = [_alias(c) for c in components]
    prefix_map: Dict[str, str] = {}
    length = 1
    while True:
        collisions = False
        seen: Set[str] = set()
        for comp, alias in zip(components, aliases):
            pfx = alias[:length]
            if pfx in seen:
                collisions = True
                break
            seen.add(pfx)
        if not collisions:
            # All prefixes are unique at this length
            for comp, alias in zip(components, aliases):
                prefix_map[comp] = alias[:length]
            break
        length += 1
        if length > max(len(a) for a in aliases):
            # Fallback: use full alias (should never happen)
            for comp, alias in zip(components, aliases):
                prefix_map[comp] = alias
            break
    return prefix_map


def _short_prefix(component: str, prefix_map: Dict[str, str]) -> str:
    """Look up the collision-aware short prefix for a component."""
    return prefix_map.get(component, _alias(component))


def _port_alias(component: str, port: str) -> str:
    safe_port = "".join(c if c.isalnum() else "_" for c in port).strip("_")
    return f"{_alias(component)}_{safe_port or 'port'}"


def _record_sort_key(r: ConnectorRecord) -> tuple:
    """Deterministic ordering for a stable diagram between runs."""
    return (r.protocol, r.caller_service, r.target_service,
            r.operation, r.endpoint)
