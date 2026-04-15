/**
 * @name NestJSInfer: Architectural Reconstruction Query (V3)
 * @description Tracks data flow from ConfigService to Axios with inter-procedural return resolution.
 * @kind table
 * @id js/nestjs-config-to-axios-final
 */

import javascript
import semmle.javascript.dataflow.TaintTracking

module ConfigToAxiosConfig implements DataFlow::ConfigSig {
  predicate isSource(DataFlow::Node source) {
    exists(DataFlow::MethodCallNode mc |
      // 1. The method being called is named 'get'
      mc.getMethodName() = "get" and
      
      // 2. Identify the receiver (the object .get() is called on)
      exists(DataFlow::Node receiver |
        receiver = mc.getReceiver() and
        (
          // Check if the variable name contains 'config' (common in NestJS)
          receiver.asExpr().(Identifier).getName().toLowerCase().matches("%config%")
          or
          // Or check if it's a property access like 'this.configService'
          receiver.asExpr().(PropAccess).getPropertyName().toLowerCase().matches("%config%")
        )
      ) and
      
      // 3. The source is the result of this call
      source = mc
      or
      exists(StringLiteral sl |
        source.asExpr() = sl
      )
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
 * Computes an integer value for simple numeric expressions.
 * Supports number literals, additions of numeric expressions, and variables
 * that locally flow from such expressions.
 */
int valueOf(Expr e) {
  // Number literal
  exists(NumberLiteral nl |
    nl = e and
    result = nl.getValue().toInt()
  )
  or
  // Addition of numeric expressions
  exists(AddExpr add, int lv, int rv |
    add = e and
    lv = valueOf(add.getLeftOperand()) and
    rv = valueOf(add.getRightOperand()) and
    result = lv + rv
  )
  or
  // Variable whose definition is a numeric expression
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
 */
string resolveExprValue(Expr e) {
  // 1. Literal strings
  result = e.(StringLiteral).getValue()
  or
  // 2. Config keys
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
  // 4. Pure numeric addition (AddExpr)
  exists(AddExpr add, int v |
    add = e and
    // No string or template literals directly in this addition:
    not exists(Expr operand |
      operand = add.getAnOperand() and
      (operand instanceof StringLiteral or operand instanceof TemplateLiteral)
    ) and
    v = valueOf(add) and
    result = "" + v
  )
  or
  // 5. String concatenation (AddExpr with a string/template literal)
  exists(AddExpr add |
    add = e and
    exists(Expr operand |
      operand = add.getAnOperand() and
      (operand instanceof StringLiteral or operand instanceof TemplateLiteral)
    ) and
    result = resolveExprValue(add.getLeftOperand()) + resolveExprValue(add.getRightOperand())
  )
  or
  // 6. Template Literals
  exists(TemplateLiteral tl | 
    tl = e and
    result = resolveTemplateElements(tl, 0)
  )
  or
  // 7. Inter-procedural Return Resolution
  exists(CallExpr call, Function f |
    call = e and
    // In JS library, we resolve the callee to a function definition
    f = call.getCallee().(VarAccess).getVariable().getAnAssignedExpr() and
    // Get all expressions returned by that function
    result = resolveExprValue(f.getAReturnStmt().getExpr())
  )
  or
  // 7b. For named function declarations
  exists(CallExpr call, FunctionDeclStmt f |
    call = e and
    f.getName() = call.getCalleeName() and
    result = resolveExprValue(f.getAReturnStmt().getExpr())
  )
  or
  // 8. Logical Expressions (The || fix)
  exists(LogicalBinaryExpr log | log = e |
    result = resolveExprValue(log.getLeftOperand()) or 
    result = resolveExprValue(log.getRightOperand())
  )
  or
  // 9. Await Expressions
  exists(AwaitExpr await | await = e |
    result = resolveExprValue(await.getOperand())
  )
  or
  // 10. SSA/Variable Resolution
  exists(VarAccess va, Expr source |
    va = e and
    DataFlow::localFlowStep*(DataFlow::valueNode(source), DataFlow::valueNode(va)) and
    not source instanceof VarAccess and
    result = resolveExprValue(source)
  )
  or
  // 11. Property Access (this.tempBaseUrl)
  exists(PropAccess pa, AssignExpr assign |
    pa = e and pa.getBase() instanceof ThisExpr and
    assign.getLhs().(PropAccess).getPropertyName() = pa.getPropertyName() and
    assign.getLhs().(PropAccess).getBase() instanceof ThisExpr and
    result = resolveExprValue(assign.getRhs())
  )
  or
  // Refined Fallback
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

string resolveUrlAtSink(DataFlow::Node sink) {
  exists(Expr e | e = sink.asExpr() and result = resolveExprValue(e))
  or
  exists(DataFlow::Node source |
    DataFlow::localFlowStep+(source, sink) and
    result = resolveExprValue(source.asExpr())
  )
}

/**
 * Derive the calling microservice name from the sink's file path.
 * Uses the relative file path and maps top-level folders like
 * `auth/`, `clubs/`, `events/`, `gateway/`, `notifications`, `users/`.
 */
string callerService(DataFlow::Node sink) {
  // auth
  result = "auth" and
  exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (p.matches("auth/%") or p.matches("%/auth/%"))
  )
  or
  // clubs
  result = "clubs" and
  exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (p.matches("clubs/%") or p.matches("%/clubs/%"))
  )
  or
  // events
  result = "events" and
  exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (p.matches("events/%") or p.matches("%/events/%"))
  )
  or
  // gateway
  result = "gateway" and
  exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (p.matches("gateway/%") or p.matches("%/gateway/%"))
  )
  or
  // notifications
  result = "notifications" and
  exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (p.matches("notifications/%") or p.matches("%/notifications/%"))
  )
  or
  // users
  result = "users" and
  exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (p.matches("users/%") or p.matches("%/users/%"))
  )
  or
  // fallback when no folder matched
  result = "unknown-service" and
  not exists(Expr e, string p |
    e = sink.asExpr() and
    p = e.getFile().getRelativePath() and
    (
      p.matches("auth/%") or p.matches("%/auth/%") or
      p.matches("clubs/%") or p.matches("%/clubs/%") or
      p.matches("events/%") or p.matches("%/events/%") or
      p.matches("gateway/%") or p.matches("%/gateway/%") or
      p.matches("notifications/%") or p.matches("%/notifications/%") or
      p.matches("users/%") or p.matches("%/users/%")
    )
  )
}

/**
 * Extracts the HTTP method (e.g., "get", "post") from an Axios call expression.
 */
string httpMethod(DataFlow::Node sink) {
  exists(MethodCallExpr axiosCall |
    sink.asExpr() = axiosCall.getAnArgument() and
    axiosCall.getReceiver().(Identifier).getName() = "axios" and
    result = axiosCall.getMethodName()
  )
}

from DataFlow::Node source, DataFlow::Node sink
where ConfigToAxios::flow(source, sink)
select 
  source,
  callerService(sink) as callerService,
  any(string s | 
    if source.asExpr() instanceof MethodCallExpr 
    then s = source.asExpr().(MethodCallExpr).getAnArgument().(StringLiteral).getValue()
    else s = "Unknown-Key"
  ) as configKey,
  sink, 
  resolveUrlAtSink(sink) as resolvedEndpoint,
  httpMethod(sink) as httpMethod