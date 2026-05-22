/**
 * AxiosConnector.qll
 *
 * Detects REST call-return connectors expressed as `axios.<method>(url, ...)`.
 *
 * WHY THIS IS A SEPARATE MODULE:
 *   The legacy `dataflow6.ql` bundled Axios detection, URL resolution and
 *   caller identification into one ~300-line query. Splitting the
 *   "what is an axios call?" concern into its own module means:
 *     1) Other REST flavours (HttpService, fetch, got) can share the
 *        resolution library without inheriting Axios-specific assumptions.
 *     2) Tests can focus on Axios patterns in isolation.
 *     3) We can delete or replace the detector without touching the
 *        shared library.
 *
 * SCOPE:
 *   Call-return only. Axios does not have a pub-sub API so every method we
 *   match is implicitly request/response.res
 */

import javascript
import semmle.javascript.dataflow.TaintTracking
import lib.Connector
import lib.ExprResolution
import lib.ServiceIdentification

/**
 * Set of Axios HTTP methods we treat as connectors.
 *
 * WHY A CLOSED SET:
 *   Axios exposes many ancillary helpers (`isAxiosError`, `create`,
 *   `interceptors`, ...) that are NOT architectural connectors. Matching
 *   by method name rather than structural pattern keeps the sink precise.
 *   The list is the OpenAPI-style set of HTTP verbs plus `request`, which
 *   is Axios's escape hatch for dynamic method selection.
 */
private predicate isAxiosHttpMethod(string name) {
  name = "get" or name = "post" or name = "put" or name = "patch" or
  name = "delete" or name = "head" or name = "options" or name = "request"
}

/**
 * Taint-tracking configuration: config reads flow to Axios URL arguments.
 *
 * WHY TAINT AND NOT PLAIN VALUE FLOW:
 *   NestJS services stash the result of `configService.get(...)` into a
 *   class field (e.g. `this.usersServiceBase`) and then concatenate it
 *   into a template literal at call time. Value flow alone does NOT cross
 *   the concatenation; taint flow does, because string concat is a
 *   tainted step by default.
 */
module ConfigToAxiosConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) {
    exists(DataFlow::MethodCallNode mc |
      mc.getMethodName() = "get" and
      exists(DataFlow::Node receiver |
        receiver = mc.getReceiver() and
        (
          receiver.asExpr().(Identifier).getName().toLowerCase().matches("%config%")
          or
          receiver.asExpr().(PropAccess).getPropertyName().toLowerCase().matches("%config%")
        )
      ) and
      source = mc
    )
  }

  predicate isSink(DataFlow::Node sink) {
    exists(MethodCallExpr axiosCall |
      axiosCall.getReceiver().(Identifier).getName() = "axios" and
      isAxiosHttpMethod(axiosCall.getMethodName()) and
      sink = DataFlow::valueNode(axiosCall.getArgument(0))
    )
  }

  /**
   * Bridges `this.foo = x` → `this.foo` reads across methods.
   * Without this additional step, we lose flow from the constructor's
   * assignment to the request-time read in `register()` / `getUsers()` /
   * etc.
   */
  predicate isAdditionalFlowStep(DataFlow::Node pred, DataFlow::Node succ) {
    exists(DataFlow::PropWrite pw, DataFlow::PropRead pr |
      pw.getPropertyName() = pr.getPropertyName() and
      pw.getBase().asExpr() instanceof ThisExpr and
      pr.getBase().asExpr() instanceof ThisExpr and
      pred = pw.getRhs() and
      succ = pr
    )
  }
}

module ConfigToAxios = TaintTracking::Global<ConfigToAxiosConfig>;

/**
 * An `axios.<method>(url, ...)` invocation, registered as a `Connector` so
 * the unified query can include it.
 *
 * WHY WE EXTEND `MethodCallExpr` AND NOT `DataFlow::Node`:
 *   The connector is an AST-level entity. We occasionally need access to
 *   `getMethodName`, `getReceiver`, the URL argument etc., and
 *   MethodCallExpr exposes those directly. `getLocation` is inherited.
 */
class AxiosCall extends Connector, MethodCallExpr {
  AxiosCall() {
    this.getReceiver().(Identifier).getName() = "axios" and
    isAxiosHttpMethod(this.getMethodName())
  }

  override string getProtocol() { result = "rest" }

  override string getOperation() { result = this.getMethodName() }

  override string getCallerService() { result = callerServiceForExpr(this) }

  override string getEndpoint() { result = resolveExprValue(this.getArgument(0)) }

  override string getTargetService() { result = targetServiceFromUrl(this.getEndpoint()) }

  /**
   * Finds a config key that taint-flows to this call's URL argument, if any.
   *
   * WHY AT MOST ONE KEY PER CALL:
   *   In practice each call uses a single `*_SERVICE_URL` env var. If a
   *   codebase concatenates several config values we emit one row per key,
   *   which the composition stage can deduplicate by sink location.
   *
   * WHY WE DELEGATE TO `configKeyFlowsTo/2`:
   *   The positive and negative branches both need to know "did a config
   *   source flow to this sink?". Extracting that question into a dedicated
   *   predicate lets CodeQL memoise the flow relation once and reuse it
   *   for both branches, instead of materialising the taint graph twice.
   *   That turned out to be critical for keeping memory bounded when the
   *   taint graph is large.
   */
  override string getConfigKey() {
    configKeyFlowsTo(result, this)
    or
    result = "" and not configKeyFlowsTo(_, this)
  }
}

/**
 * Helper: true if a `configService.get("<result>")` call taint-flows into
 * the URL argument of `call`. Shared between the positive and negative
 * branches of `AxiosCall.getConfigKey` so CodeQL only computes the flow
 * relation once.
 *
 * Kept private to this module so other connectors can't accidentally
 * become sinks for the Axios-specific taint configuration.
 */
private predicate configKeyFlowsTo(string key, AxiosCall call) {
  exists(DataFlow::Node source, DataFlow::Node sink, MethodCallExpr mc |
    ConfigToAxios::flow(source, sink) and
    sink = DataFlow::valueNode(call.getArgument(0)) and
    mc = source.asExpr() and
    key = mc.getAnArgument().(StringLiteral).getValue()
  )
}
