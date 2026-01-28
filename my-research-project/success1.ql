/**
 * @name Trace Every Step of Clubs URL
 * @kind path-problem
 * @problem.severity info
 * @id js/research/trace-clubs-url
 */
/** This query traces the complete data flow path from the configuration service
call to the final URL variable, including intermediate steps such as property
assignments and template literals.*/
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
    // BRIDGE 1: The Teleport (Assignment to Property -> Reading of Property)
    exists(AssignExpr assign, PropAccess read |
      assign.getLhs().(PropAccess).getPropertyName().toLowerCase().matches("%baseurl") and
      read.getPropertyName().toLowerCase().matches("%baseurl") and
      // Teleport from the VALUE being assigned to the PLACE it is read
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
select sink.getNode(), source, sink, "Full data flow path found from Config to URL!"