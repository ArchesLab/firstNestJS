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

/**
 * Resolves an expression to all its possible string values.
 * Returns multiple results for branching (if/else, ternary).
 */
string resolveExprValue(Expr e) {
  // Case 1: String literal - return the literal value directly
  result = e.(StringLiteral).getValue()
  or
  // Case 2: ConfigService.get() call - wrap the config key in braces
  exists(MethodCallExpr mc | mc = e |
    mc.getMethodName() = "get" and
    result = "{" + mc.getAnArgument().(StringLiteral).getValue() + "}"
  )
  or
  // Case 3: Variable reference - trace back using SSA/data flow
  exists(VarAccess va, Expr source |
    va = e and
    DataFlow::localFlowStep*(DataFlow::valueNode(source), DataFlow::valueNode(va)) and
    not source instanceof VarAccess and
    result = resolveExprValue(source)
  )
  or
  // Case 4: Await expression - resolve the inner expression
  result = resolveExprValue(e.(AwaitExpr).getOperand())
  or
  // Case 5: Function call - find return statements and resolve their values
  exists(CallExpr call, Function f, ReturnStmt ret |
    call = e and
    f = call.getCallee().(VarAccess).getVariable().getAnAssignedExpr() and
    ret.getContainer() = f and
    result = resolveExprValue(ret.getExpr())
  )
  or
  // Case 5b: Named function declaration call
  exists(CallExpr call, FunctionDeclStmt f, ReturnStmt ret |
    call = e and
    f.getName() = call.getCalleeName() and
    ret.getContainer() = f and
    result = resolveExprValue(ret.getExpr())
  )
  or
  // Case 6: Ternary/conditional expression - resolve both branches
  exists(ConditionalExpr ce | ce = e |
    result = resolveExprValue(ce.getConsequent()) or
    result = resolveExprValue(ce.getAlternate())
  )
  or
  // Case 7: LogicalOrExpr (x || y) - resolve both sides
  exists(LogicalOrExpr lor | lor = e |
    result = resolveExprValue(lor.getLeftOperand()) or
    result = resolveExprValue(lor.getRightOperand())
  )
  or
  // Case 8: this.property access - trace through property assignments
  exists(PropAccess pa, AssignExpr assign |
    pa = e and
    pa.getBase() instanceof ThisExpr and
    assign.getLhs().(PropAccess).getPropertyName() = pa.getPropertyName() and
    assign.getLhs().(PropAccess).getBase() instanceof ThisExpr and
    result = resolveExprValue(assign.getRhs())
  )
  or
  // Case 9: Template literal - recursively resolve and concatenate
  exists(TemplateLiteral tl | tl = e |
    result = resolveTemplateElements(tl, 0)
  )
  or
  // Fallback: if no other case matches, return the expression as a placeholder
  not e instanceof StringLiteral and
  not e instanceof MethodCallExpr and
  not e instanceof VarAccess and
  not e instanceof AwaitExpr and
  not e instanceof CallExpr and
  not e instanceof ConditionalExpr and
  not e instanceof LogicalOrExpr and
  not (e instanceof PropAccess and e.(PropAccess).getBase() instanceof ThisExpr) and
  not e instanceof TemplateLiteral and
  result = "{" + e.toString() + "}"
}

/**
 * Recursively resolves template literal elements and concatenates them.
 */
string resolveTemplateElements(TemplateLiteral tl, int i) {
  // Base case: no more elements
  i = tl.getNumElement() and result = ""
  or
  // Recursive case: resolve current element and concatenate with rest
  exists(string head, string tail |
    i < tl.getNumElement() and
    tail = resolveTemplateElements(tl, i + 1) and
    (
      // Static template element (literal string part)
      head = tl.getElement(i).(TemplateElement).getRawValue()
      or
      // Dynamic expression - resolve it (exclude TemplateElement by requiring a resolved value)
      exists(Expr elem |
        elem = tl.getElement(i) and
        head = resolveExprValue(elem)
      )
    ) and
    result = head + tail
  )
}

/**
 * Resolves the URL for a given sink node.
 */
string resolveTemplateWithConfigKeys(DataFlow::Node sink) {
  exists(MethodCallExpr axiosCall |
    DataFlow::valueNode(axiosCall.getArgument(0)) = sink |
    // Direct template literal argument
    exists(TemplateLiteral tl |
      tl = axiosCall.getArgument(0) and
      result = resolveTemplateElements(tl, 0)
    )
    or
    // Variable that flows from a template literal
    exists(DataFlow::Node mid, TemplateLiteral tl |
      DataFlow::valueNode(axiosCall.getArgument(0)) = mid and
      DataFlow::localFlowStep+(DataFlow::valueNode(tl), mid) and
      result = resolveTemplateElements(tl, 0)
    )
    or
    // Fallback for unresolved cases
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