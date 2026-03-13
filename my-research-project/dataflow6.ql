/**
 * @name NestJSInfer: Architectural Reconstruction Query (V3)
 * @description Tracks data flow from ConfigService to Axios with inter-procedural return resolution.
 * @kind table
 * @id js/nestjs-config-to-axios-final
 */

import javascript
import semmle.javascript.dataflow.TaintTracking

module ConfigToAxiosConfig implements DataFlow::ConfigSig {
//   predicate isSource(DataFlow::Node source) {
//     exists(MethodCallExpr mc |
//       mc.getMethodName() = "get" and
//       mc.getAnArgument().(StringLiteral).getValue().toUpperCase().matches("%SERVICE_URL%") and
//       source = DataFlow::valueNode(mc)
//     )
//   }
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
    )
  }

  predicate isSink(DataFlow::Node sink) {
    exists(MethodCallExpr axiosCall |
      (axiosCall.getReceiver().(Identifier).getName() = "axios" or 
       axiosCall.getMethodName().matches("get|post|put|delete")) and
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
  // 3. String Concatenation (AddExpr)
  exists(AddExpr add | 
    add = e and
    result = resolveExprValue(add.getLeftOperand()) + resolveExprValue(add.getRightOperand())
  )
  or
  // 4. Template Literals
  exists(TemplateLiteral tl | 
    tl = e and
    result = resolveTemplateElements(tl, 0)
  )
  or
  // 5. Inter-procedural Return Resolution
  exists(CallExpr call, Function f |
    call = e and
    // In JS library, we resolve the callee to a function definition
    f = call.getCallee().(VarAccess).getVariable().getAnAssignedExpr() and
    // Get all expressions returned by that function
    result = resolveExprValue(f.getAReturnStmt().getExpr())
  )
  or
  // 5b. For named function declarations
  exists(CallExpr call, FunctionDeclStmt f |
    call = e and
    f.getName() = call.getCalleeName() and
    result = resolveExprValue(f.getAReturnStmt().getExpr())
  )
  or
  // 6. Logical Expressions (The || fix)
  exists(LogicalBinaryExpr log | log = e |
    result = resolveExprValue(log.getLeftOperand()) or 
    result = resolveExprValue(log.getRightOperand())
  )
  or
  // 7. Await Expressions
  exists(AwaitExpr await | await = e |
    result = resolveExprValue(await.getOperand())
  )
  or
  // 8. SSA/Variable Resolution
  exists(VarAccess va, Expr source |
    va = e and
    DataFlow::localFlowStep*(DataFlow::valueNode(source), DataFlow::valueNode(va)) and
    not source instanceof VarAccess and
    result = resolveExprValue(source)
  )
  or
  // 9. Property Access (this.tempBaseUrl)
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

from DataFlow::Node source, DataFlow::Node sink
where ConfigToAxios::flow(source, sink)
select 
  source, 
  source.asExpr().(MethodCallExpr).getAnArgument().(StringLiteral).getValue() as configKey,
  sink, 
  resolveUrlAtSink(sink) as resolvedEndpoint

