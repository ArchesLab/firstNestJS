/**
 * @name ConfigService to Axios Global Flow
 * @description Tracks data flow from ConfigService.get() to axios calls using global taint tracking
 * @kind path-problem
 * @problem.severity info
 * @id js/config-to-axios-global
 */

import javascript
import semmle.javascript.dataflow.TaintTracking

module ConfigToAxiosConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) {
    exists(MethodCallExpr mc |
      mc.getMethodName() = "get" and
      mc.getAnArgument().(StringLiteral).getValue().toUpperCase().matches("%SERVICE_URL%") and
      source = DataFlow::valueNode(mc)
    )
  }

  predicate isSink(DataFlow::Node sink) {
    exists(MethodCallExpr axiosCall |
      axiosCall.getReceiver().(Identifier).getName() = "axios" and
      sink = DataFlow::valueNode(axiosCall.getArgument(0))
    )
  }

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
import ConfigToAxios::PathGraph

string getConfigKey(DataFlow::Node source) {
  exists(MethodCallExpr mc |
    mc = source.asExpr() and
    mc.getMethodName() = "get" and
    result = mc.getAnArgument().(StringLiteral).getValue()
  )
}

string getAxiosMethod(DataFlow::Node sink) {
  exists(MethodCallExpr axiosCall |
    DataFlow::valueNode(axiosCall.getArgument(0)) = sink and
    result = axiosCall.getMethodName()
  )
}

from ConfigToAxios::PathNode source, ConfigToAxios::PathNode sink
where ConfigToAxios::flowPath(source, sink)
select sink.getNode(), source, sink,
  "Config key '" + getConfigKey(source.getNode()) + "' flows to axios." + getAxiosMethod(sink.getNode()) + "()"