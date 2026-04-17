/**
 * GrpcConnector.qll
 *
 * Detects gRPC call-return connectors in TypeScript / NestJS codebases.
 *
 * WHY GRPC NEEDS ITS OWN MODULE (AND DOES NOT FIT IN AXIOS'):
 *   gRPC is syntactically just a method call on a stub object:
 *       `await userService.getUser(request)`
 *   To the AST this is indistinguishable from any other method call. What
 *   makes it a gRPC connector is the PROVENANCE of the receiver:
 *     - It came from `ClientGrpc.getService<T>("UserService")` (NestJS)
 *     - Or from `new proto.UserService(addr, creds)` (@grpc/grpc-js)
 *     - Or from `createClient(UserServiceDefinition, channel)` (nice-grpc)
 *
 *   Detecting gRPC therefore means tracking the stub VARIABLE back to its
 *   definition, then emitting any method call on that variable as a
 *   connector. This is fundamentally different from Axios where the
 *   receiver is always the `axios` identifier.
 *
 * SCOPE: CALL-RETURN UNARY RPC ONLY.
 *   gRPC supports four call modes: unary, server-stream, client-stream,
 *   bidi-stream. The latter three are stream-oriented and behave more like
 *   pub-sub, so they are explicitly out of scope for this project (per the
 *   user's "no pub-sub" requirement). We detect unary calls, which are
 *   identified by being a simple `await stub.method(req)` with no stream
 *   callback usage.
 */

import javascript
import lib.Connector
import lib.ExprResolution
import lib.ServiceIdentification

/**
 * Recognises a gRPC-adjacent import in the containing file.
 *
 * WHY FILE-LEVEL RATHER THAN CALL-LEVEL:
 *   The stub variable may be declared far from the call site (e.g. injected
 *   via the NestJS DI container). Checking that the FILE imports a gRPC
 *   package is a cheap, high-precision gate that avoids treating arbitrary
 *   `obj.method()` calls as gRPC calls.
 */
private predicate fileUsesGrpc(File f) {
  exists(ImportDeclaration id | id.getFile() = f |
    id.getImportedPath().getValue() = "@grpc/grpc-js" or
    id.getImportedPath().getValue() = "@grpc/proto-loader" or
    id.getImportedPath().getValue() = "nice-grpc" or
    id.getImportedPath().getValue() = "nice-grpc-common" or
    // NestJS microservices client for gRPC transport.
    id.getImportedPath().getValue() = "@nestjs/microservices"
  )
}

/**
 * Finds variables that hold a gRPC stub.
 *
 * Three ways a variable becomes a stub (matching the three client
 * libraries above). We unify them as "this variable is a gRPC client" and
 * then let the `GrpcCall` class consume the information.
 */
private predicate isGrpcStubVariable(Variable v, string serviceName) {
  fileUsesGrpc(v.getADeclaration().getFile()) and
  (
    // Pattern A: NestJS `this.client.getService<UserService>("UserService")`
    // Canonical example:
    //   const userService = this.userGrpcClient.getService<UserService>('UserService');
    // The string literal IS the proto service name we emit as target.
    exists(MethodCallExpr mc |
      v.getAnAssignedExpr() = mc and
      mc.getMethodName() = "getService" and
      serviceName = mc.getArgument(0).(StringLiteral).getValue()
    )
    or
    // Pattern B: `new proto.UserService(address, creds)` or a dotted
    // constructor whose rightmost component names the service.
    // We pull the constructor name out of the `NewExpr`'s callee as a
    // best-effort service label.
    exists(NewExpr ne |
      v.getAnAssignedExpr() = ne and
      serviceName = ne.getCallee().(PropAccess).getPropertyName()
    )
    or
    // Pattern C: `createClient(UserServiceDefinition, channel)` (nice-grpc).
    // The first argument is a definition object whose name ends in
    // `Definition`; we strip the suffix as a conventional service label.
    exists(CallExpr ce, string rawName |
      v.getAnAssignedExpr() = ce and
      ce.getCalleeName() = "createClient" and
      rawName = ce.getArgument(0).(Identifier).getName() and
      (
        serviceName = rawName.regexpCapture("(.*)Definition$", 1)
        or
        not rawName.regexpMatch(".*Definition$") and serviceName = rawName
      )
    )
  )
}

/**
 * A method invocation on a known gRPC stub.
 *
 * EXCLUSION LIST:
 *   The stub object also exposes helpers that are not architectural
 *   connectors (e.g. `close`, `waitForReady`, `getChannel`). We filter
 *   those out so they don't pollute the recovered architecture.
 *
 *   Long-term the paper's philosophy says "prefer over-approximation and
 *   let rules filter"; short-term this curated list removes obvious noise.
 */
private predicate isGrpcInfrastructureMethod(string name) {
  name = "close" or name = "waitForReady" or name = "getChannel" or
  name = "bindAsync" or name = "addService" or name = "start"
}

/**
 * A unary gRPC call expressed as `stub.method(request)`.
 *
 * WHY WE ASSUME UNARY:
 *   Streaming calls typically chain `.on("data", ...)` / `.on("end", ...)`
 *   handlers on the returned object, or the method's generated type
 *   annotates a stream. Distinguishing the two statically is possible with
 *   type information but adds complexity. We approximate by treating every
 *   plain stub method call as call-return; if a streaming call slips
 *   through, the architectural diagram still shows the right caller and
 *   target - it just labels a stream as if it were unary, which is less
 *   harmful than missing the connector entirely.
 */
class GrpcCall extends Connector, MethodCallExpr {
  string serviceName;

  GrpcCall() {
    exists(Variable stub |
      isGrpcStubVariable(stub, serviceName) and
      this.getReceiver() = stub.getAnAccess() and
      not isGrpcInfrastructureMethod(this.getMethodName())
    )
  }

  override string getProtocol() { result = "grpc" }

  override string getOperation() { result = this.getMethodName() }

  override string getCallerService() { result = callerServiceForExpr(this) }

  /**
   * For gRPC, the target is the proto service name (e.g. `UserService`).
   * We lower-case it and strip a trailing `Service` / `Grpc` suffix so it
   * matches the microservice folder name when the convention holds
   * (e.g. `UserService` -> `users` does NOT happen automatically; authors
   * should document their mapping). When the heuristic can't normalise,
   * we emit the raw proto name prefixed with `grpc:` to make it obvious
   * this is a gRPC target, not a REST service folder.
   */
  override string getTargetService() {
    exists(string normalised |
      normalised = serviceName.toLowerCase().regexpReplaceAll("(service|grpc)$", "") |
      (
        knownService(normalised) and result = normalised
        or
        not knownService(normalised) and result = "grpc:" + serviceName
      )
    )
  }

  /**
   * Endpoint uses gRPC's canonical `/Service/Method` shape, matching the
   * on-the-wire path. This lets the renderer show ports with the same
   * structure as HTTP paths, keeping the diagram legible across protocols.
   *
   * If the first argument is a resolvable string (some codebases build
   * request objects with a `.path` field), we append a hint; otherwise the
   * endpoint is just `/<ServiceName>/<methodName>`.
   */
  override string getEndpoint() { result = "/" + serviceName + "/" + this.getMethodName() }

  /**
   * Config key is captured when a `configService.get(...)` call appears in
   * the same file as this gRPC call.
   *
   * WHY FILE-LEVEL PROXIMITY RATHER THAN SCOPE-AWARE TAINT:
   *   gRPC server addresses usually reach the stub constructor via several
   *   hops (module factory, provider, options object). A full taint
   *   analysis like the Axios module already has would be overkill for
   *   gRPC because the architectural value of knowing the exact env-var
   *   is lower (proto mismatches cause more real bugs than address typos).
   *   File-level proximity catches the common case where the module and
   *   the consumer live in the same file, while staying simple and fast.
   *
   *   When multiple config keys are read in the same file, we emit one
   *   row per key. Downstream rule checking can cross-reference by
   *   location.
   */
  override string getConfigKey() {
    exists(MethodCallExpr cfgGet |
      cfgGet.getFile() = this.getFile() and
      cfgGet.getMethodName() = "get" and
      cfgGet.getReceiver().(PropAccess).getPropertyName().toLowerCase().matches("%config%") and
      result = cfgGet.getArgument(0).(StringLiteral).getValue()
    )
    or
    not exists(MethodCallExpr cfgGet |
      cfgGet.getFile() = this.getFile() and
      cfgGet.getMethodName() = "get" and
      cfgGet.getReceiver().(PropAccess).getPropertyName().toLowerCase().matches("%config%")
    ) and
    result = ""
  }
}
