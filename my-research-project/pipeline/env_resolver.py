"""Loading and substituting ``.env`` values into resolved-URL placeholders.

All behaviour is inherited verbatim from ``tests/query.py``:
- Multiple ``.env`` files are merged into a single dict; later paths overwrite
  earlier ones on duplicate keys.
- Non-existent paths print ``Skipping: <path> (Not found)`` and continue.
- Placeholders matched by ``r"\\{([A-Z][A-Z0-9_]*_URL)\\}"`` are substituted by
  ``{<env-value>}`` (braces preserved around the value, as the human report
  format expects).
"""

from __future__ import annotations

import os
import re
from typing import Dict, List, Optional, Tuple

# The placeholder pattern the Axios analysis emits via ``resolveExprValue``.
# Matches uppercase env-variable names ending in ``_URL`` wrapped in braces.
ENV_PLACEHOLDER_RE = re.compile(r"\{([A-Z][A-Z0-9_]*_URL)\}")

# Regex used to infer the callee service name from an env-var like
# ``USERS_SERVICE_URL`` → ``users``.
SERVICE_URL_NAME_RE = re.compile(r"([A-Z][A-Z0-9]*)_SERVICE_URL$")


def load_env_files(env_paths: List[str]) -> Dict[str, str]:
    """Merge the given ``.env`` files into a single dict.

    Files are read in the order given; later files overwrite earlier ones on
    duplicate keys. Missing files are skipped with a notice on stdout — the
    same behaviour as the original ``load_all_envs``.
    """
    combined: Dict[str, str] = {}
    for path in env_paths:
        if not os.path.exists(path):
            print(f"Skipping: {path} (Not found)")
            continue
        print(f"Loading variables from: {path}")
        with open(path, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    key, value = line.split("=", 1)
                    combined[key.strip()] = value.strip().strip('"').strip("'")
    return combined


def extract_env_placeholders(raw_url: str) -> List[str]:
    """Return every ``{ENV_VAR_URL}`` placeholder name found in ``raw_url``.

    Lower-case path parameters (e.g. ``{userId}``) are ignored by construction
    because the regex requires the first character to be uppercase.
    """
    return ENV_PLACEHOLDER_RE.findall(raw_url)


def resolve_url_placeholders(
    raw_url: str, env_vars: Dict[str, str]
) -> Optional[Tuple[str, List[str]]]:
    """Substitute ``{ENV}`` placeholders with ``{<actual-value>}``.

    Returns a ``(resolved_url, placeholders)`` pair, or ``None`` if any
    placeholder is missing from ``env_vars`` or no placeholders are present.
    The ``None`` return preserves the original behaviour of skipping rows that
    cannot be fully resolved.
    """
    placeholders = extract_env_placeholders(raw_url)
    if not placeholders:
        return None

    resolved = raw_url
    for env_var in placeholders:
        if env_var not in env_vars:
            print(f"DEBUG: Missing env var: {env_var}")
            return None
        resolved = resolved.replace(f"{{{env_var}}}", f"{{{env_vars[env_var]}}}")
    return resolved, placeholders


def infer_callee_service(env_vars: List[str]) -> str:
    """Infer the callee service name from env var names like ``USERS_SERVICE_URL``.

    Returns a lowercase service name, a comma-separated list for multiple
    matches, or ``"unknown"`` if no env var matches the ``*_SERVICE_URL``
    pattern. This helper is kept for downstream consumers (e.g. future
    gRPC/Redis orchestrators) that may want to infer targets independently of
    URL path parsing.
    """
    services = set()
    for env_var in env_vars:
        m = SERVICE_URL_NAME_RE.match(env_var)
        if m:
            services.add(m.group(1).lower())
    if not services:
        return "unknown"
    if len(services) == 1:
        return next(iter(services))
    return ",".join(sorted(services))
