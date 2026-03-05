/**
 * @name ConfigService to Axios Global Flow
 * @description Tracks data flow from ConfigService.get() to axios calls using global taint tracking
 * @kind path-problem
 * @problem.severity info
 * @id js/config-to-axios-global
 */

import javascript
import semmle.javascript.dataflow.TaintTracking

/**
 * Global taint tracking configuration.
 * CodeQL automatically handles:
 *   - Interprocedural flow (across function calls)
 *   - Property assignments (this.prop = value -> this.prop)
 *   - Template literals (`${value}`)
 *   - String concatenation (a + b)
 *   - Variable assignments and reads
 */
module ConfigToAxiosConfig implements DataFlow::ConfigSig {
  /**
   * SOURCE: ConfigService.get() calls that retrieve service URLs
   * Example: this.configService.get('USERS_SERVICE_URL')
   */
  predicate isSource(DataFlow::Node source) {
    exists(MethodCallExpr mc |
      mc.getMethodName() = "get" and
      mc.getAnArgument().(StringLiteral).getValue().toUpperCase().matches("%SERVICE_URL%") and
      source.asExpr() = mc
    )
  }

  /**
   * SINK: First argument to any axios method call
   * Example: axios.get(url), axios.post(url, data), this.axios.delete(url)
   */
  predicate isSink(DataFlow::Node sink) {
    exists(MethodCallExpr axiosCall |
      axiosCall.getReceiver().(Identifier).getName().matches("%axios%") and
      sink.asExpr() = axiosCall.getArgument(0)
    )
    or
    // Also handle: this.httpService.axiosRef.get(url)
    exists(MethodCallExpr axiosCall |
      axiosCall.getReceiver().(PropAccess).getPropertyName() = "axiosRef" and
      sink.asExpr() = axiosCall.getArgument(0)
    )
  }

  /**
   * Optional: Prevent flow through sanitizers (if needed)
   * Uncomment and customize if you want to block flow through certain nodes
   */
  // predicate isBarrier(DataFlow::Node node) {
  //   // Example: block flow through URL validation functions
  //   exists(CallExpr call |
  //     call.getCalleeName() = "sanitizeUrl" and
  //     node.asExpr() = call
  //   )
  // }
}

// Create the global taint tracking module
module ConfigToAxios = TaintTracking::Global<ConfigToAxiosConfig>;

// Import PathGraph for path visualization in CodeQL UI
import ConfigToAxios::PathGraph

/**
 * Helper to extract the config key from the source
 */
string getConfigKey(DataFlow::Node source) {
  exists(MethodCallExpr mc |
    mc = source.asExpr() and
    mc.getMethodName() = "get" and
    result = mc.getAnArgument().(StringLiteral).getValue()
  )
}

/**
 * Helper to get axios method name from sink
 */
string getAxiosMethod(DataFlow::Node sink) {
  exists(MethodCallExpr axiosCall |
    sink.asExpr() = axiosCall.getArgument(0) and
    result = axiosCall.getMethodName()
  )
}

from ConfigToAxios::PathNode source, ConfigToAxios::PathNode sink
where ConfigToAxios::flowPath(source, sink)
select sink.getNode(), source, sink,
  "Config key '" + getConfigKey(source.getNode()) + "' flows to axios." + getAxiosMethod(sink.getNode()) + "()"