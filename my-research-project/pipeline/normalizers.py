"""
normalizers.py - per-protocol cleanup of raw CodeQL endpoints.

WHY A SEPARATE STAGE:
  CodeQL emits endpoints in protocol-specific raw forms:
    REST:  "{USERS_SERVICE_URL}/users/42"
    gRPC:  "/UserService/getUser"
    Redis: "KEY(user:{id})"

  Each needs slightly different canonicalisation before it can be
  displayed as a port label or compared across architectures. Putting the
  protocol-specific logic HERE (rather than inside the renderer) keeps
  the renderer free of `if protocol == "...":` branches.

ONE FUNCTION PER PROTOCOL:
  Dispatching through a registry (`NORMALIZERS[protocol]`) lets new
  protocols slot in by registering a function - no changes required in
  the renderer or pipeline.
"""

import re
from dataclasses import replace
from typing import Callable, Dict

from .models import ConnectorRecord


# ---------------------------------------------------------------------------
# REST
# ---------------------------------------------------------------------------

# Strips the `{CONFIG_KEY}` placeholder that `ExprResolution.qll` prepends
# to resolved URLs. The resulting path is what the renderer shows as a
# port label on the target component, matching how the original
# `converter.py` behaved.
_REST_CONFIG_PLACEHOLDER = re.compile(r"^\{[^}]*\}")


def _normalise_rest(record: ConnectorRecord) -> ConnectorRecord:
    """Strip the leading `{CONFIG_KEY}` placeholder from REST endpoints.

    WHY WE KEEP THE PATH AS-IS OTHERWISE:
      The path itself (e.g. `/users/{userId}`) is the architectural
      identifier. Collapsing `{userId}` would hide legitimate variation
      in the diagram. We therefore touch ONLY the config placeholder
      that is an artefact of our resolver, not a property of the system.
    """
    cleaned = _REST_CONFIG_PLACEHOLDER.sub("", record.endpoint)
    return replace(record, endpoint=cleaned or "/")


# ---------------------------------------------------------------------------
# gRPC
# ---------------------------------------------------------------------------

def _normalise_grpc(record: ConnectorRecord) -> ConnectorRecord:
    """gRPC endpoints come out in canonical `/Service/Method` form from
    CodeQL. No further cleanup needed, but we keep the stage explicit so
    future adjustments (e.g. stripping a package prefix) have an obvious
    home.
    """
    return record


# ---------------------------------------------------------------------------
# Redis
# ---------------------------------------------------------------------------

# Matches the `KEY(...)` wrapper emitted by RedisConnector.qll. We unwrap
# it in the renderer to show just the key pattern as the port label.
_REDIS_KEY_WRAPPER = re.compile(r"^KEY\((.*)\)$")


def _normalise_redis(record: ConnectorRecord) -> ConnectorRecord:
    """Unwrap `KEY(x)` to `x`; leave bare markers like `KEY(*)` alone.

    WHY WE DON'T REWRITE THE WRAPPER IN CODEQL:
      The wrapper is deliberately there: at the CodeQL layer we want an
      unambiguous signal that an endpoint is a Redis key and not a URL
      path or gRPC method. The Python renderer is where presentation
      happens, so unwrapping belongs here.
    """
    match = _REDIS_KEY_WRAPPER.match(record.endpoint)
    if not match:
        return record
    unwrapped = match.group(1)
    # Strip resolver placeholder prefix if present, same as REST.
    unwrapped = _REST_CONFIG_PLACEHOLDER.sub("", unwrapped)
    return replace(record, endpoint=unwrapped or "*")


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

NORMALIZERS: Dict[str, Callable[[ConnectorRecord], ConnectorRecord]] = {
    "rest": _normalise_rest,
    "grpc": _normalise_grpc,
    "redis": _normalise_redis,
}


def normalise(record: ConnectorRecord) -> ConnectorRecord:
    """Dispatch to the protocol's normaliser; identity if none known.

    WHY AN IDENTITY FALLBACK:
      The parser already filters to known protocols, but the pipeline
      should not silently drop records just because we forgot to
      register a normaliser. An identity fallback keeps data flowing.
    """
    handler = NORMALIZERS.get(record.protocol, lambda r: r)
    return handler(record)
