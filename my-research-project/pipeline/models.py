"""Protocol-agnostic data model for a single CPC connector edge.

A ``ConnectorEdge`` is one reconstructed connector in the architecture graph:
a requirer port in ``caller_service`` invokes a provider port whose logical
endpoint is ``resolved_url`` using ``method`` semantics.

The model deliberately keeps ``resolved_url`` as an opaque string so the same
dataclass can carry an Axios URL, a gRPC path (``/pkg.Service/Method``), a
Redis key, or a NestJS Transport.REDIS routing pattern.
"""

from dataclasses import dataclass
from typing import Tuple


@dataclass(frozen=True)
class ConnectorEdge:
    location: str
    caller_service: str
    env_vars: Tuple[str, ...]
    resolved_url: str
    method: str

    @property
    def dedup_key(self) -> Tuple[str, Tuple[str, ...], str]:
        """Key used to deduplicate edges with identical callers / env vars / method."""
        return (self.caller_service, self.env_vars, self.method)
