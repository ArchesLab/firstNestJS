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

/**
 * Reconstructs a template literal string, replacing this.prop references
 * with the config key they were assigned from.
 * e.g. `${this.usersServiceBase}/users` → {USERS_SERVICE_URL}/users
 */
string reconstructTemplate(TemplateLiteral tl, int i) {
  i = tl.getNumElement() and result = ""
  or
  exists(string head, string tail |
    i < tl.getNumElement() and
    tail = reconstructTemplate(tl, i + 1) and
    (
      // Static text parts of the template
      exists(TemplateElement te | te = tl.getElement(i) | head = te.getRawValue())
      or
      // Replace this.prop with {CONFIG_KEY}
      exists(PropAccess pa, AssignExpr assign, MethodCallExpr mc |
        pa = tl.getElement(i) and
        pa.getBase() instanceof ThisExpr and
        assign.getLhs().(PropAccess).getPropertyName() = pa.getPropertyName() and
        assign.getLhs().(PropAccess).getBase() instanceof ThisExpr and
        mc = assign.getRhs() and
        mc.getMethodName() = "get" and
        head = "{" + mc.getAnArgument().(StringLiteral).getValue() + "}"
      )
      or
      // Fallback for anything else
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

/**
 * Resolves the URL passed to an axios call, replacing this.prop references
 * with their config keys. Handles both direct template literals and
 * template literals assigned to a variable before being passed to axios.
 */
string resolveTemplateWithConfigKeys(DataFlow::Node sink) {
  exists(MethodCallExpr axiosCall |
    DataFlow::valueNode(axiosCall.getArgument(0)) = sink |
    // Case 1: axios.post(`${this.usersServiceBase}/users`) - direct template literal
    exists(TemplateLiteral tl |
      tl = axiosCall.getArgument(0) and
      result = reconstructTemplate(tl, 0)
    )
    or
    // Case 2: const url = `${this.usersServiceBase}/users`; axios.post(url)
    exists(DataFlow::Node mid, TemplateLiteral tl |
      DataFlow::valueNode(axiosCall.getArgument(0)) = mid and
      DataFlow::localFlowStep+(DataFlow::valueNode(tl), mid) and
      result = reconstructTemplate(tl, 0)
    )
    or
    // Fallback: if we can't resolve the template, just show the sink as-is
    not exists(TemplateLiteral tl | tl = axiosCall.getArgument(0)) and
    not exists(DataFlow::Node mid, TemplateLiteral tl |
      DataFlow::valueNode(axiosCall.getArgument(0)) = mid and
      DataFlow::localFlowStep+(DataFlow::valueNode(tl), mid)
    ) and
    result = "<unresolved>"
  )
}

from ConfigToAxios::PathNode source, ConfigToAxios::PathNode sink
where ConfigToAxios::flowPath(source, sink)
select sink.getNode().getLocation().toString(), source, sink,
  "Config key '" + getConfigKey(source.getNode()) +
  "' flows to axios." + sink