/**
 * Protocol-agnostic source-side helpers for CPC extraction: detecting
 * `ConfigService.get()` calls and modelling the standard `this.X = Y`
 * property-transfer flow step.
 *
 * Extracted from dataflow6.ql's `isSource` and `isAdditionalFlowStep`
 * predicates — same behaviour.
 */

import javascript
import semmle.javascript.dataflow.DataFlow

/**
 * Holds if `source` is a `ConfigService.get(...)` (or compatible) call — i.e.
 * a method named `get` invoked on a receiver whose identifier name or
 * property name contains `config` (case-insensitive), or equivalently a
 * `StringLiteral` (the broad-source behaviour inherited from dataflow6.ql).
 */
predicate isConfigServiceGetCall(DataFlow::Node source) {
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
  or
  exists(StringLiteral sl | source.asExpr() = sl)
}

/**
 * Additional flow step that propagates values written to `this.X` to reads
 * of `this.X` with the same property name.
 */
predicate thisPropertyFlowStep(DataFlow::Node pred, DataFlow::Node succ) {
  exists(DataFlow::PropWrite pw, DataFlow::PropRead pr |
    pw.getPropertyName() = pr.getPropertyName() and
    pw.getBase().asExpr() instanceof ThisExpr and
    pr.getBase().asExpr() instanceof ThisExpr and
    pred = pw.getRhs() and
    succ = pr
  )
}
