/**
 * @name Trace Config to Network Method
 * @kind path-problem
 * @problem.severity info
 * @id js/research/trace-to-axios-method
 */

import javascript
import semmle.javascript.dataflow.TaintTracking

module ClubsTraceConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) {
    exists(MethodCallExpr mc |
      mc.getMethodName() = "get" and
      mc.getAnArgument().getStringValue().toLowerCase().matches("%_service_url") and
      source.asExpr() = mc
    )
  }

  predicate isSink(DataFlow::Node sink) {
    // SINK: The URL argument of any axios method call
    exists(MethodCallExpr axiosCall |
      axiosCall.getReceiver().(Identifier).getName() = "axios" and
      // This matches get, post, delete, patch, etc.
      axiosCall.getArgument(0) = sink.asExpr()
    )
  }

  predicate isAdditionalFlowStep(DataFlow::Node node1, DataFlow::Node node2) {
    // BRIDGE 1: The STRICT Teleport (Same name matching)
    exists(AssignExpr assign, PropAccess read, string propName |
      propName.toLowerCase().matches("%baseurl") and
      assign.getLhs().(PropAccess).getPropertyName() = propName and
      read.getPropertyName() = propName and
      node1.asExpr() = assign.getRhs() and
      node2.asExpr() = read
    )
    or
    // BRIDGE 2: The Template Literal Smear
    exists(TemplateLiteral tl |
      node1.asExpr() = tl.getAnElement() and
      node2.asExpr() = tl
    )
  }
}

module ClubsTrace = TaintTracking::Global<ClubsTraceConfig>;
import ClubsTrace::PathGraph

from ClubsTrace::PathNode source, ClubsTrace::PathNode sink, MethodCallExpr axiosCall
where 
  ClubsTrace::flowPath(source, sink) and
  axiosCall.getArgument(0) = sink.getNode().asExpr()
select 
  sink.getNode(), 
  source, 
  sink, 
  "URL from " + source.getNode().asExpr().(MethodCallExpr).getAnArgument().getStringValue() + 
  " used in axios." + axiosCall.getMethodName() + "()"