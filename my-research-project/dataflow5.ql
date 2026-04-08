/**
 * @name NestJSInfer: Architectural Reconstruction Query
 * @description Tracks data flow from ConfigService.get() to axios calls and resolves full URLs.
 * @kind table
 * @id js/nestjs-config-to-axios
 */

import javascript
import semmle.javascript.dataflow.TaintTracking

module ConfigToAxiosConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) {
    exists(MethodCallExpr mc |
      mc.getMethodName() = "get" and
      // Target keys like 'USERS_SERVICE_URL'
      mc.getAnArgument().(StringLiteral).getValue().toUpperCase().matches("%SERVICE_URL%") and
      source = DataFlow::valueNode(mc)
    )
  }

  predicate isSink(DataFlow::Node sink) {
    exists(MethodCallExpr axiosCall |
      // Targets axios.get(), axios.post(), or axios(url)
      (axiosCall.getReceiver().(Identifier).getName() = "axios" or 
       axiosCall.getMethodName().matches("get|post|put|delete")) and
      sink = DataFlow::valueNode(axiosCall.getArgument(0))
    )
  }

  predicate isAdditionalFlowStep(DataFlow::Node pred, DataFlow::Node succ) {
    // Tracks member variable assignments (e.g., this.url = configUrl)
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

/**
 * Recursively resolves an expression to its logical string representation.
 */
string resolveExprValue(Expr e) {
  // 1. Literal strings (e.g., "/users")
  result = e.(StringLiteral).getValue()
  or
  // 2. Config keys (e.g., "{USERS_SERVICE_URL}")
  exists(MethodCallExpr mc | 
    mc = e and mc.getMethodName() = "get" and
    result = "{" + mc.getAnArgument().(StringLiteral).getValue() + "}"
  )
  or
  // 3. String Concatenation (The fix for your /users bug)
  exists(AddExpr add | 
    add = e and
    result = resolveExprValue(add.getLeftOperand()) + resolveExprValue(add.getRightOperand())
  )
  or
  // 4. Template Literals (Recursive)
  exists(TemplateLiteral tl | 
    tl = e and
    result = resolveTemplateElements(tl, 0)
  )
  or
  // 5. SSA/Variable Resolution
  exists(VarAccess va, Expr source |
    va = e and
    DataFlow::localFlowStep*(DataFlow::valueNode(source), DataFlow::valueNode(va)) and
    not source instanceof VarAccess and
    result = resolveExprValue(source)
  )
  or
  // 6. Property Access (this.url)
  exists(PropAccess pa, AssignExpr assign |
    pa = e and pa.getBase() instanceof ThisExpr and
    assign.getLhs().(PropAccess).getPropertyName() = pa.getPropertyName() and
    assign.getLhs().(PropAccess).getBase() instanceof ThisExpr and
    result = resolveExprValue(assign.getRhs())
  )
  or
  // Fallback: Only wrap unknown logic nodes, NOT literals
  not e instanceof StringLiteral and
  not e instanceof AddExpr and
  not e instanceof TemplateLiteral and
  not e instanceof MethodCallExpr and
  not e instanceof VarAccess and
  not (e instanceof PropAccess and e.(PropAccess).getBase() instanceof ThisExpr) and
  result = "{" + e.toString() + "}"
}

/**
 * Resolves elements within a TemplateLiteral (backticks).
 */
string resolveTemplateElements(TemplateLiteral tl, int i) {
  i = tl.getNumElement() and result = ""
  or
  exists(string head, string tail |
    i < tl.getNumElement() and
    tail = resolveTemplateElements(tl, i + 1) and
    (
      head = tl.getElement(i).(TemplateElement).getRawValue()
      or
      exists(Expr elem |
        elem = tl.getElement(i) and
        not elem instanceof TemplateElement and
        head = resolveExprValue(elem)
      )
    ) and
    result = head + tail
  )
}

/**
 * Final resolution for the Sink node.
 */
string resolveUrlAtSink(DataFlow::Node sink) {
  exists(Expr e | 
    e = sink.asExpr() and
    result = resolveExprValue(e)
  )
  or
  // If the sink is a variable, find its assigned template or string
  exists(DataFlow::Node source |
    DataFlow::localFlowStep+(source, sink) and
    result = resolveExprValue(source.asExpr())
  )
}

from DataFlow::Node source, DataFlow::Node sink
where ConfigToAxios::flow(source, sink)
select 
  source, 
  sink, 
  resolveUrlAtSink(sink) as resolvedEndpoint