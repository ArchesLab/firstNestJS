/**
 * Protocol-agnostic expression / URL resolution helpers.
 *
 * Extracted from dataflow6.ql. These predicates recover the logical string
 * representation of a JavaScript/TypeScript expression that contributes to a
 * URL, a gRPC target, a Redis key, or any other string-valued argument of
 * interest to a static CPC extractor.
 *
 * Kept semantics-preserving with the in-place definitions previously inlined
 * in dataflow6.ql — the resolution algorithm is unchanged; only the physical
 * location of the predicates moved.
 */

import javascript
import semmle.javascript.dataflow.DataFlow

/**
 * Computes an integer value for simple numeric expressions.
 * Supports number literals, additions of numeric expressions, and variables
 * that locally flow from such expressions.
 */
int valueOf(Expr e) {
  exists(NumberLiteral nl |
    nl = e and
    result = nl.getValue().toInt()
  )
  or
  exists(AddExpr add, int lv, int rv |
    add = e and
    lv = valueOf(add.getLeftOperand()) and
    rv = valueOf(add.getRightOperand()) and
    result = lv + rv
  )
  or
  exists(VarAccess va, Expr source, int v |
    va = e and
    DataFlow::localFlowStep*(DataFlow::valueNode(source), DataFlow::valueNode(va)) and
    not source instanceof VarAccess and
    v = valueOf(source) and
    result = v
  )
}

/**
 * Recursively resolves an expression to its logical string representation.
 *
 * Handles literals, config keys, numeric and string concatenation, template
 * literals, inter-procedural returns, logical expressions, await, SSA
 * variables, and `this.*` property reads with matching property writes.
 */
string resolveExprValue(Expr e) {
  // 1. Literal strings
  result = e.(StringLiteral).getValue()
  or
  // 2. Config keys (e.g. configService.get('USERS_SERVICE_URL'))
  exists(MethodCallExpr mc |
    mc = e and mc.getMethodName() = "get" and
    result = "{" + mc.getAnArgument().(StringLiteral).getValue() + "}"
  )
  or
  // 3. Numeric literals
  exists(NumberLiteral nl |
    nl = e and
    result = nl.getValue()
  )
  or
  // 4. Pure numeric addition
  exists(AddExpr add, int v |
    add = e and
    not exists(Expr operand |
      operand = add.getAnOperand() and
      (operand instanceof StringLiteral or operand instanceof TemplateLiteral)
    ) and
    v = valueOf(add) and
    result = "" + v
  )
  or
  // 5. String concatenation (AddExpr with a string/template literal operand)
  exists(AddExpr add |
    add = e and
    exists(Expr operand |
      operand = add.getAnOperand() and
      (operand instanceof StringLiteral or operand instanceof TemplateLiteral)
    ) and
    result = resolveExprValue(add.getLeftOperand()) + resolveExprValue(add.getRightOperand())
  )
  or
  // 6. Template literals
  exists(TemplateLiteral tl |
    tl = e and
    result = resolveTemplateElements(tl, 0)
  )
  or
  // 7. Inter-procedural return resolution (variable-assigned functions)
  exists(CallExpr call, Function f |
    call = e and
    f = call.getCallee().(VarAccess).getVariable().getAnAssignedExpr() and
    result = resolveExprValue(f.getAReturnStmt().getExpr())
  )
  or
  // 7b. Named function declarations
  exists(CallExpr call, FunctionDeclStmt f |
    call = e and
    f.getName() = call.getCalleeName() and
    result = resolveExprValue(f.getAReturnStmt().getExpr())
  )
  or
  // 8. Logical expressions (||, &&)
  exists(LogicalBinaryExpr log | log = e |
    result = resolveExprValue(log.getLeftOperand()) or
    result = resolveExprValue(log.getRightOperand())
  )
  or
  // 9. Await expressions
  exists(AwaitExpr await | await = e |
    result = resolveExprValue(await.getOperand())
  )
  or
  // 10. SSA / Variable resolution
  exists(VarAccess va, Expr source |
    va = e and
    DataFlow::localFlowStep*(DataFlow::valueNode(source), DataFlow::valueNode(va)) and
    not source instanceof VarAccess and
    result = resolveExprValue(source)
  )
  or
  // 11. `this.X` property reads resolved against matching `this.X = ...` writes
  exists(PropAccess pa, AssignExpr assign |
    pa = e and pa.getBase() instanceof ThisExpr and
    assign.getLhs().(PropAccess).getPropertyName() = pa.getPropertyName() and
    assign.getLhs().(PropAccess).getBase() instanceof ThisExpr and
    result = resolveExprValue(assign.getRhs())
  )
  or
  // Refined fallback for unrecognised expression shapes
  not e instanceof StringLiteral and
  not e instanceof AddExpr and
  not e instanceof TemplateLiteral and
  not e instanceof MethodCallExpr and
  not e instanceof CallExpr and
  not e instanceof LogicalBinaryExpr and
  not e instanceof AwaitExpr and
  not e instanceof VarAccess and
  not (e instanceof PropAccess and e.(PropAccess).getBase() instanceof ThisExpr) and
  result = "{" + e.toString() + "}"
}

/**
 * Resolves elements within a template literal (backticks) by concatenating
 * raw template parts with recursively-resolved interpolated expressions.
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
 * Final resolution at a data-flow sink: either the sink expression itself or
 * any expression that locally flows into it.
 */
string resolveUrlAtSink(DataFlow::Node sink) {
  exists(Expr e | e = sink.asExpr() and result = resolveExprValue(e))
  or
  exists(DataFlow::Node source |
    DataFlow::localFlowStep+(source, sink) and
    result = resolveExprValue(source.asExpr())
  )
}
