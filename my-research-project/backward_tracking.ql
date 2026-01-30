/**
 * @name Trace Backwards: Network Call to Config
 * @kind path-problem
 */

import javascript
import semmle.javascript.dataflow.TaintTracking

module ClubsReverseConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) {
    exists(MethodCallExpr axiosCall |
      // Matches axios.get(), axios.post(), or axios()
      (axiosCall.getReceiver().(Identifier).getName() = "axios" or 
       axiosCall.getCalleeName() = "axios") and
      // We start at the URL argument
      source.asExpr() = axiosCall.getArgument(0)
    )
  }

  predicate isSink(DataFlow::Node sink) {
    exists(MethodCallExpr mc, Expr arg |
      mc.getMethodName() = "get" and
      arg = mc.getAnArgument() and
      // This catches 'STRING_LITERALS' or CONSTANT_VARIABLES
      (
        arg.getStringValue().toLowerCase().matches("%_service_url") or
        arg.(Identifier).getName().toLowerCase().matches("%_service_url")
      ) and
      sink.asExpr() = arg
    )
  }

  predicate isAdditionalFlowStep(DataFlow::Node node1, DataFlow::Node node2) {
    // 1. REVERSED BRIDGE: Template Literals (`` `${baseUrl}/path` `` -> `baseUrl`)
    exists(TemplateLiteral tl |
      node1.asExpr() = tl and
      node2.asExpr() = tl.getAnElement()
    )
    or
    // 2. REVERSED BRIDGE: String Concatenation ("http://" + host -> host)
    exists(BinaryExpr add |
      add.getOperator() = "+" and
      node1.asExpr() = add and
      (node2.asExpr() = add.getLeftOperand() or node2.asExpr() = add.getRightOperand())
    )
    or
    // 3. REVERSED BRIDGE: Property Access (obj.prop -> obj)
    exists(PropAccess pa |
      node1.asExpr() = pa and
      node2.asExpr() = pa.getBase()
    )
    or
    // 4. THE ULTIMATE BACKWARD STEP: Variable Use -> Variable Definition
    DataFlow::localFlowStep(node2, node1)
  }
}

module ClubsReverse = TaintTracking::Global<ClubsReverseConfig>;
import ClubsReverse::PathGraph

from ClubsReverse::PathNode source, ClubsReverse::PathNode sink
where ClubsReverse::flowPath(source, sink)
select sink.getNode(), source, sink, "Config key $@ is used in this network call.", sink.getNode(), sink.getNode().asExpr().toString()