 /**

 * @name Trace Backwards: Network Call to Config

 * @kind path-problem

 * @problem.severity info

 * @id js/research/trace-backwards-network

 */



import javascript

import semmle.javascript.dataflow.TaintTracking



module ClubsReverseConfig implements DataFlow::ConfigSig {

  predicate isSource(DataFlow::Node source) {

    exists(MethodCallExpr axiosCall |

      axiosCall.getReceiver().(Identifier).getName() = "axios" and

      source.asExpr() = axiosCall.getArgument(0)

    )

  }



  predicate isSink(DataFlow::Node sink) {

    exists(MethodCallExpr mc |

      mc.getMethodName() = "get" and

      mc.getAnArgument().getStringValue().toLowerCase().matches("%_service_url") and

      sink.asExpr() = mc

    )

  }



  predicate isAdditionalFlowStep(DataFlow::Node node1, DataFlow::Node node2) {

    // REVERSED BRIDGE 1: Property Read -> Property Write
    exists(AssignExpr assign, PropAccess read, string propName |
      propName.toLowerCase().matches("%baseurl") and
      assign.getLhs().(PropAccess).getPropertyName() = propName and
      read.getPropertyName() = propName and
      node1.asExpr() = read and
      node2.asExpr() = assign.getRhs()
    )
    or
    // REVERSED BRIDGE 2: Template Literal -> Its Elements
    exists(TemplateLiteral tl |
      node1.asExpr() = tl and
      node2.asExpr() = tl.getAnElement()
    )
    or
    // REVERSED BRIDGE 3: The "Bulletproof" Variable Bridge
    // This tells CodeQL: "If you are at a variable use, jump back to any local assignment."
    DataFlow::localFlowStep(node2, node1)
  }
}


module ClubsReverse = TaintTracking::Global<ClubsReverseConfig>;
import ClubsReverse::PathGraph

from ClubsReverse::PathNode source, ClubsReverse::PathNode sink
where ClubsReverse::flowPath(source, sink)
select source.getNode(), source, sink, "Backward path found to config source."