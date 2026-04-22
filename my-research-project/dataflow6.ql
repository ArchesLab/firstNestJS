/**
 * @name NestJSInfer: Architectural Reconstruction Query (V3)
 * @description Tracks data flow from ConfigService to Axios with inter-procedural return resolution.
 * @kind table
 * @id js/nestjs-config-to-axios-final
 */

import javascript
import semmle.javascript.dataflow.TaintTracking
import lib.ConfigSource
import lib.ExprResolution
import lib.ServiceIdentification

module ConfigToAxiosConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) { isConfigServiceGetCall(source) }

  predicate isSink(DataFlow::Node sink) {
    exists(MethodCallExpr axiosCall |
      axiosCall.getReceiver().(Identifier).getName() = "axios" and
      sink = DataFlow::valueNode(axiosCall.getArgument(0))
    )
  }

  predicate isAdditionalFlowStep(DataFlow::Node pred, DataFlow::Node succ) {
    thisPropertyFlowStep(pred, succ)
  }
}

module ConfigToAxios = TaintTracking::Global<ConfigToAxiosConfig>;

/**
 * Extracts the HTTP method (e.g., "get", "post") from an Axios call expression.
 * This is the protocol-specific port-type extractor for Axios; the gRPC and
 * Redis variants will live alongside this query with analogous predicates.
 */
string httpMethod(DataFlow::Node sink) {
  exists(MethodCallExpr axiosCall |
    sink.asExpr() = axiosCall.getAnArgument() and
    axiosCall.getReceiver().(Identifier).getName() = "axios" and
    result = axiosCall.getMethodName()
  )
}

from DataFlow::Node source, DataFlow::Node sink
where ConfigToAxios::flow(source, sink)
select
  source,
  callerService(sink) as callerService,
  any(string s |
    if source.asExpr() instanceof MethodCallExpr
    then s = source.asExpr().(MethodCallExpr).getAnArgument().(StringLiteral).getValue()
    else s = "Unknown-Key"
  ) as configKey,
  sink,
  resolveUrlAtSink(sink) as resolvedEndpoint,
  httpMethod(sink) as httpMethod
