/**
 * @name Trace Config to URL (Isolated Paths)
 * @kind path-problem
 * @problem.severity info
 * @id js/research/trace-isolated-paths
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
    exists(VariableDeclarator decl |
      decl.getBindingPattern().(Identifier).getName() = "url" and
      sink.asExpr() = decl.getInit()
    )
  }

  predicate isAdditionalFlowStep(DataFlow::Node node1, DataFlow::Node node2) {
    // BRIDGE 1: The STRICT Teleport
    // We use 'propName' to ensure the property written to is the SAME one being read.
    exists(AssignExpr assign, PropAccess read, string propName |
      propName.toLowerCase().matches("%baseurl") and
      assign.getLhs().(PropAccess).getPropertyName() = propName and
      read.getPropertyName() = propName and
      // Flow from the value being assigned into the property being read
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

from ClubsTrace::PathNode source, ClubsTrace::PathNode sink
where ClubsTrace::flowPath(source, sink)
select sink.getNode(), source, sink, 
  "Isolated path found ending in function: " + sink.getNode().asExpr().getEnclosingFunction().getName()