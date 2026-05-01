"""
models.py - the single record type the pipeline passes around.

WHY A DATACLASS INSTEAD OF THE OLD DICT:
  The legacy converter passed around dicts with string keys. That meant
  every stage had to know the exact key names and typos failed silently.
  A frozen dataclass:
    - Lets the editor / type-checker catch renames.
    - Makes the schema the CodeQL query promises to emit explicit.
    - Is hashable, so we can deduplicate connections with plain `set()`
      instead of the tuple-gymnastics in the old `converter.py`.
"""

from dataclasses import dataclass
from typing import Optional


# The set of protocols we know how to render. Kept here (not scattered
# through the renderer) so a new protocol only needs to be added in ONE
# place when we extend the system.
KNOWN_PROTOCOLS = frozenset({"rest", "grpc", "redis"})


@dataclass(frozen=True)
class ConnectorRecord:
    """One call-return connector invocation recovered by CodeQL.

    Fields mirror the CodeQL query output in `all_connectors.ql`, so the
    parser can populate them positionally.

    WHY FROZEN:
      Every stage downstream treats records as immutable facts. Freezing
      catches accidental mutation and makes the record hashable for
      deduplication.
    """

    protocol: str         # "rest" | "grpc" | "redis" (see KNOWN_PROTOCOLS)
    caller_service: str   # workspace folder that made the call
    operation: str        # HTTP verb / gRPC method / Redis command
    target_service: str   # target component name (or "unknown-service")
    endpoint: str         # URL path, gRPC service/method, Redis KEY(...)
    config_key: str       # env var name, or "" if none
    location: str         # CodeQL source location string for debugging

    def is_resolved(self) -> bool:
        """True when both ends of the connector are known services.

        Used by the renderer to decide whether to draw a solid edge or
        a dashed "unresolved" edge. Mirrors the ROSDiscover idea of
        flagging recovered architectures that contain ⊤ (top / unknown)
        elements.
        """
        return (self.caller_service != "unknown-service"
                and self.target_service != "unknown-service"
                and not self.target_service.startswith("grpc:"))


def normalise_protocol(raw: str) -> Optional[str]:
    """Canonicalise the protocol label, returning `None` for unknowns.

    WHY A HELPER:
      CodeQL could in principle emit a protocol we haven't taught the
      renderer about yet. We'd rather skip that row than crash, so the
      parser uses this helper to gate records.
    """
    lowered = raw.strip().lower()
    return lowered if lowered in KNOWN_PROTOCOLS else None
