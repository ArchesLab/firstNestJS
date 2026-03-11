/**
 * @name ConfigService to Axios Global Flow
 * @description Tracks data flow from ConfigService.get() to axios calls using global taint tracking
 * @kind table
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

string reconstructTemplate(TemplateLiteral tl, int i) {
  i = tl.getNumElement() and result = ""
  or
  exists(string head, string tail |
    i < tl.getNumElement() and
    tail = reconstructTemplate(tl, i + 1) and
    (
      exists(TemplateElement te | te = tl.getElement(i) | head = te.getRawValue())
      or
      exists(PropAccess pa, AssignExpr assign, MethodCallExpr mc |
        pa = tl.getElement(i) and
        pa.getBase() instanceof ThisExpr and
        assign.getLhs().(PropAccess).getPropertyName() = pa.getPropertyName() and
        assign.getLhs().(PropAccess).getBase() instanceof ThisExpr and
        DataFlow::localFlowStep*(DataFlow::valueNode(mc), DataFlow::valueNode(assign.getRhs())) and
        mc.getMethodName() = "get" and
        head = "{" + mc.getAnArgument().(StringLiteral).getValue() + "}"
      )
      or
      exists(Expr e |
        e = tl.getElement(i) and
        not (e instanceof PropAccess and e.(PropAccess).getBase() instanceof ThisExpr) and
        not e instanceof TemplateElement |
        head = "{" + e.toString() + "}"
      )
    ) and
    result = head + tail
  )
}

string resolveTemplateWithConfigKeys(DataFlow::Node sink) {
  exists(MethodCallExpr axiosCall |
    DataFlow::valueNode(axiosCall.getArgument(0)) = sink |
    exists(TemplateLiteral tl |
      tl = axiosCall.getArgument(0) and
      result = reconstructTemplate(tl, 0)
    )
    or
    exists(DataFlow::Node mid, TemplateLiteral tl |
      DataFlow::valueNode(axiosCall.getArgument(0)) = mid and
      DataFlow::localFlowStep+(DataFlow::valueNode(tl), mid) and
      result = reconstructTemplate(tl, 0)
    )
    or
    not exists(TemplateLiteral tl | tl = axiosCall.getArgument(0)) and
    not exists(DataFlow::Node mid, TemplateLiteral tl |
      DataFlow::valueNode(axiosCall.getArgument(0)) = mid and
      DataFlow::localFlowStep+(DataFlow::valueNode(tl), mid)
    ) and
    result = "<unresolved>"
  )
}

from DataFlow::Node source, DataFlow::Node sink
where ConfigToAxios::flow(source, sink)
select source, sink, resolveTemplateWithConfigKeys(sink)