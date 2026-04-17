/**
 * ServiceIdentification.qll
 *
 * Maps a location in source code to the name of the microservice that owns
 * that code (the caller in a call-return connector).
 *
 * WHY A MODULE (AS OPPOSED TO INLINE CODE):
 *   ROSDiscover treats each ROS node as a component instance. Its identity
 *   comes from the CMake package that builds it. For a NestJS monorepo the
 *   analogous identity comes from the top-level workspace folder
 *   (`auth/`, `users/`, ...) that the file lives in.
 *
 *   Every connector (Axios, gRPC, Redis, ...) needs the same caller-side
 *   attribution, so we centralise it here instead of copy-pasting a six-way
 *   `or` in every query.
 *
 * HOW TO EXTEND FOR A NEW WORKSPACE FOLDER:
 *   Add one row to `knownService/1` below. The caller predicate is derived
 *   from that one list so there is a single source of truth.
 */

import javascript

/**
 * Declares the set of known microservice folder names at the repo root.
 *
 * WHY A PREDICATE RATHER THAN A HARD-CODED `or`-chain: a predicate lets the
 * unknown-service fallback be expressed once with `not knownService(_)`
 * rather than repeating every branch (as the legacy `dataflow6.ql` did).
 */
predicate knownService(string name) {
  name = "auth" or
  name = "clubs" or
  name = "events" or
  name = "gateway" or
  name = "notifications" or
  name = "users"
}

/**
 * True if `path` lives inside the workspace folder for `service`.
 * We match both `service/...` (repo root) and `.../service/...` (nested or
 * worktree-style paths) so the analysis works regardless of where the
 * snapshot root is rooted.
 */
private predicate pathBelongsToService(string path, string service) {
  knownService(service) and
  (path.matches(service + "/%") or path.matches("%/" + service + "/%"))
}

/**
 * Returns the name of the microservice that contains `f`.
 * Falls back to `"unknown-service"` so downstream consumers always get a
 * value, following the same ⊤-style over-approximation philosophy as
 * ExprResolution.qll.
 */
string callerServiceForFile(File f) {
  exists(string path | path = f.getRelativePath() |
    pathBelongsToService(path, result)
    or
    result = "unknown-service" and
    not exists(string s | pathBelongsToService(path, s))
  )
}

/** Convenience wrapper when the caller has an `Expr`. */
string callerServiceForExpr(Expr e) { result = callerServiceForFile(e.getFile()) }

/** Convenience wrapper when the caller has a `DataFlow::Node`. */
string callerServiceForNode(DataFlow::Node n) { result = callerServiceForExpr(n.asExpr()) }

/**
 * Heuristic: extract the target microservice name from a resolved URL path.
 *
 * WHY A HEURISTIC RATHER THAN A GROUND-TRUTH TABLE:
 *   Our sample repo happens to route `/users`, `/clubs`, `/events`, ... on
 *   each microservice by convention, so the first path segment IS the
 *   target service. Real systems will vary; centralising this heuristic
 *   here means a reader who wants to plug in their own mapping edits ONE
 *   predicate, not every connector.
 *
 *   Returns `"unknown-service"` when the first segment does not match a
 *   known workspace folder, so the visualiser can render an "unresolved"
 *   edge rather than dropping the call entirely.
 */
bindingset[resolvedUrl]
string targetServiceFromUrl(string resolvedUrl) {
  // Strip everything up to and including the first `}` that closes the
  // `{CONFIG_KEY}` placeholder produced by ExprResolution, then take the
  // segment after the first `/`.
  exists(string afterPlaceholder, string firstSeg |
    afterPlaceholder = resolvedUrl.regexpCapture("\\{[^}]*\\}(.*)", 1) and
    firstSeg = afterPlaceholder.regexpCapture("/([^/?#]+).*", 1) and
    (
      knownService(firstSeg) and result = firstSeg
      or
      not knownService(firstSeg) and result = "unknown-service"
    )
  )
  or
  // URL did not start with a `{...}` placeholder - fall back to the first
  // path segment of the URL itself.
  not resolvedUrl.regexpMatch("\\{[^}]*\\}.*") and
  exists(string firstSeg |
    firstSeg = resolvedUrl.regexpCapture("[^/]*/([^/?#]+).*", 1) and
    (
      knownService(firstSeg) and result = firstSeg
      or
      not knownService(firstSeg) and result = "unknown-service"
    )
  )
}
