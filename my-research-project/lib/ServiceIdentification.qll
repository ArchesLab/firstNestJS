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
 * HOW SERVICES ARE IDENTIFIED:
 *   Prefer explicit monorepo project roots (`apps/<name>/...`,
 *   `services/<name>/...`, `packages/<name>/...`, `libs/<name>/...`).
 *   That covers real Nx/Turborepo-style repositories such as Daytona,
 *   where the owning service is `apps/api`, not a nested domain folder
 *   like `apps/api/src/auth`.
 *
 *   The small sample repo used by tests has services directly at the repo
 *   root (`auth/`, `users/`, ...), so we keep those as a fallback.
 *   We also recover root-level NestJS service folders such as
 *   `gateway/src/...` and `token/src/...` from multi-service example repos.
 *
 *   Some CodeQL databases are created from inside a single backend service
 *   directory. In those databases every relative path starts at `src/...`,
 *   so there is no parent folder to recover. For those single-root NestJS
 *   backends we use a stable synthetic service name.
 */

import javascript

/** Services used by the small checked-in sample application. */
private predicate builtInSampleService(string name) {
  name = "auth" or
  name = "clubs" or
  name = "events" or
  name = "gateway" or
  name = "notifications" or
  name = "users"
}

/**
 * Extracts an owner service from common monorepo project layouts.
 *
 * Examples:
 *   apps/api/src/auth/foo.ts        -> api
 *   services/billing/src/index.ts   -> billing
 *   packages/runner/src/cache.ts    -> runner
 *   libs/toolbox-api-client/src.ts  -> toolbox-api-client
 *
 * WHY `bindingset[path]`:
 *   `path.matches(...)` is a FILTER (it tells you whether a given `path`
 *   matches a pattern) - it does not ENUMERATE paths. Without a
 *   bindingset CodeQL can't verify that `path` will always come bound.
 */
bindingset[path]
private predicate monorepoServiceFromPath(string path, string service) {
  service = path.regexpCapture("^([^/]+/)?(apps|services|packages|libs)/([^/]+)/.*", 3)
}

/**
 * Extracts root-level service folders from simple multi-service repos.
 *
 * Example:
 *   gateway/src/users.controller.ts -> gateway
 *   token/src/token.controller.ts   -> token
 */
bindingset[path]
private predicate rootServiceFromPath(string path, string service) {
  service = path.regexpCapture("^(.*?/)?([^/]+)/(src|test)/.*", 2)
}

bindingset[path]
private predicate singleRootNestServiceFromPath(string path, string service) {
  service = "nest-server" and
  (
    path.matches("src/%") or
    path.matches("test/%")
  )
}

/**
 * True if `path` lives inside a root-level sample service folder.
 * We keep this separate from monorepo extraction so `apps/api/src/auth/...`
 * resolves to `api`, not to the nested folder `auth`.
 */
bindingset[path]
private predicate samplePathBelongsToService(string path, string service) {
  builtInSampleService(service) and
  path.matches(service + "/%")
}

/**
 * Declares the set of service names known to the analysis. This includes
 * sample services and service names discovered from any file under common
 * monorepo project roots.
 */
predicate knownService(string name) {
  builtInSampleService(name)
  or
  exists(File f | monorepoServiceFromPath(f.getRelativePath(), name))
  or
  exists(File f | rootServiceFromPath(f.getRelativePath(), name))
  or
  exists(File f | singleRootNestServiceFromPath(f.getRelativePath(), name))
}

/**
 * Maps a protocol/interface/domain-ish name to the deployed service folder.
 *
 * gRPC code often names the proto surface `AuthService` while the actual
 * deployable unit is `auth-service/`.  Rendering the proto surface as a
 * component invents an extra service.  This predicate keeps component
 * identity tied to recovered project roots, while callers can still use the
 * proto/RPC name as the endpoint label.
 */
bindingset[rawName]
string canonicalServiceName(string rawName) {
  exists(string lowerName, string baseName, string serviceFolder |
    lowerName = rawName.toLowerCase().regexpReplaceAll("_", "-") and
    baseName = lowerName.regexpReplaceAll("(-?service|-?grpc)$", "") and
    knownService(serviceFolder) and
    (
      serviceFolder = lowerName and result = serviceFolder
      or
      serviceFolder = baseName and result = serviceFolder
      or
      serviceFolder = baseName + "-service" and result = serviceFolder
    )
  )
}

/** True if `path` lives inside the workspace folder for `service`. */
bindingset[path]
private predicate pathBelongsToService(string path, string service) {
  monorepoServiceFromPath(path, service)
  or
  rootServiceFromPath(path, service)
  or
  singleRootNestServiceFromPath(path, service)
  or
  samplePathBelongsToService(path, service)
}

/**
 * Returns the name of the microservice that contains `f`.
 * Falls back to `"unknown-service"` so downstream consumers always get a
 * value, following the same ⊤-style over-approximation philosophy as
 * ExprResolution.qll.
 *
 * WHY INLINE `f.getRelativePath()` INSTEAD OF WRAPPING IN AN OUTER
 * `exists(string path | path = f.getRelativePath() | ...)`:
 *   The outer `exists` introduces a free variable whose binding CodeQL
 *   must reason about across both OR branches AND the nested
 *   `not exists`. That reasoning failed on some toolchain versions with
 *   "'path' is not bound to a value". Inlining the expression removes
 *   the free variable and lets each branch be type-checked independently.
 */
string callerServiceForFile(File f) {
  pathBelongsToService(f.getRelativePath(), result)
  or
  result = "unknown-service" and
  not exists(string s | pathBelongsToService(f.getRelativePath(), s))
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
