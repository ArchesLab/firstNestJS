/**
 * @name Microservice Connector Recovery (Axios, gRPC, Redis)
 * @description Unified query that asks each connector module for its
 *              architectural records and merges them into a single table.
 * @kind table
 * @id js/microservice-connector-recovery
 *
 * WHY ONE QUERY INSTEAD OF THREE:
 *   Downstream tools (the Python pipeline, the PlantUML renderer, the
 *   rule checker) all want a single uniform stream of connector records.
 *   Running three separate queries and concatenating their outputs would
 *   force the Python side to know about each protocol; instead the
 *   abstraction lives here and the pipeline just consumes rows.
 *
 * WHY WE IMPORT EVERY CONNECTOR BUT REFERENCE THE BASE CLASS ONLY:
 *   The `import connectors.*` lines exist purely for their SIDE EFFECT of
 *   making CodeQL instantiate the `AxiosCall`, `GrpcCall`, and `RedisCall`
 *   subclasses of `Connector`. The `from ... where ... select` below sees
 *   every `Connector` in the database - no protocol-specific branching
 *   required. Adding a new protocol means adding ONE import line here
 *   (and one new .qll under connectors/) - zero changes to the select.
 */

import javascript
import lib.Connector
import connectors.AxiosConnector
import connectors.GrpcConnector
import connectors.RedisConnector

/**
 * Every row is a single call-return connector invocation.
 *
 * Output schema (pipe-separated when rendered by CodeQL's CSV/table
 * decoder, exactly matching the existing `tests/final_result.txt` format
 * so the Python side stays backwards-compatible):
 *
 *   protocol | callerService | operation | targetService | endpoint | configKey | location
 */
from Connector c
select
  c.getProtocol() as protocol,
  c.getCallerService() as callerService,
  c.getOperation() as operation,
  c.getTargetService() as targetService,
  c.getEndpoint() as endpoint,
  c.getConfigKey() as configKey,
  c as location
