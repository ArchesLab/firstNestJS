/**
 * Maps a data-flow sink back to the owning microservice based on its source
 * file path.
 *
 * Extracted from dataflow6.ql verbatim — semantics preserved.  The hard-coded
 * service list (`auth`, `clubs`, `events`, `gateway`, `notifications`,
 * `users`) is the same one the original predicate used.  Paths that do not
 * match any of these six prefixes fall back to `unknown-service`.
 */

import javascript
import semmle.javascript.dataflow.DataFlow

/**
 * Derive the calling microservice name from the sink's file path.
 * Uses the relative file path and maps top-level folders like
 * `auth/`, `clubs/`, `events/`, `gateway/`, `notifications/`, `users/`.
 */
string callerService(DataFlow::Node sink) {
  result = "auth" and
  exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (p.matches("auth/%") or p.matches("%/auth/%"))
  )
  or
  result = "clubs" and
  exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (p.matches("clubs/%") or p.matches("%/clubs/%"))
  )
  or
  result = "events" and
  exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (p.matches("events/%") or p.matches("%/events/%"))
  )
  or
  result = "gateway" and
  exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (p.matches("gateway/%") or p.matches("%/gateway/%"))
  )
  or
  result = "notifications" and
  exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (p.matches("notifications/%") or p.matches("%/notifications/%"))
  )
  or
  result = "users" and
  exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (p.matches("users/%") or p.matches("%/users/%"))
  )
  or
  result = "unknown-service" and
  not exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (
      p.matches("auth/%") or p.matches("%/auth/%") or
      p.matches("clubs/%") or p.matches("%/clubs/%") or
      p.matches("events/%") or p.matches("%/events/%") or
      p.matches("gateway/%") or p.matches("%/gateway/%") or
      p.matches("notifications/%") or p.matches("%/notifications/%") or
      p.matches("users/%") or p.matches("%/users/%")
    )
  )
}
