/**
 * ExprResolution.qll
 *
 * Shared symbolic resolver for TypeScript expressions.
 *
 * WHY THIS EXISTS AS ITS OWN MODULE:
 *   The original `dataflow6.ql` hard-coded a ~100-line resolver inside the
 *   Axios-only query. Every connector we add (gRPC, Redis, HttpService, ...)
 *   needs the SAME resolver logic because:
 *     - URLs, gRPC server addresses, Redis keys and channel names are all
 *       produced by string-building patterns (template literals, concats,
 *       configService.get("..."), property assignments on `this.*`).
 *     - Duplicating that logic per connector would drift quickly and make
 *       misconfigurations silently undetectable in one protocol but not
 *       another.
 *   By extracting it once, every connector module can call the same
 *   `resolveExprValue` and benefit from improvements (e.g. better
 *   inter-procedural support) without touching the connectors themselves.
 *
 * PARALLEL TO ROSDISCOVER:
 *   ROSDiscover calls this stage "Component Model Recovery" - producing a
 *   symbolic summary of each node's behaviour by resolving API-call
 *   arguments. We do the same for microservice calls: reduce an `axios.post`
 *   argument, a `client.sendMessage` method selector, or a `redis.get` key
 *   down to a canonical string that can be composed at the system level.
 */

import javascript
import semmle.javascript.dataflow.TaintTracking

/**
 * Evaluates simple integer expressions (literals, additions, and variables
 * that locally flow from such expressions).
 *
 * WHY: Configurations occasionally encode ports or timeouts as integers. We
 * resolve them to make endpoint comparisons stable across equivalent
 * numeric forms (e.g. `3000` vs `1000 + 2000`).
 */
int valueOf(Expr e) {
  // Numeric literal - base case.
  exists(NumberLiteral nl |
    nl = e and
    result = nl.getValue().toInt()
  )
  or
  // Addition of numeric expressions.
  exists(AddExpr add, int lv, int rv |
    add = e and
    lv = valueOf(add.getLeftOperand()) and
    rv = valueOf(add.getRightOperand()) and
    result = lv + rv
  )
  or
  // Variable whose definition is a numeric expression.
  // We guard with `not source instanceof VarAccess` to prevent trivial
  // self-loops that would make CodeQL's fixed-point non-monotonic.
  exists(VarAccess va, Expr source, int v |
    va = e and
    DataFlow::localFlowStep*(DataFlow::valueNode(source), DataFlow::valueNode(va)) and
    not source instanceof VarAccess and
    v = valueOf(source) and
    result = v
  )
}

/**
 * Resolves `e` to a canonical string representation.
 *
 * This is the heart of the recovery: it turns expressions whose runtime
 * value depends on configuration into placeholders the composition stage
 * can later bind to concrete URLs/hosts/keys.
 *
 * The rule-set was chosen to cover the idioms we actually see in NestJS
 * codebases:
 *   1) String literals               -> themselves
 *   2) `configService.get("FOO")`    -> `"{FOO}"` (placeholder for later binding)
 *   3) Numeric literals              -> decimal string
 *   4) Pure numeric adds             -> evaluated by `valueOf`
 *   5) String concatenation (`+`)    -> recursive resolve of both sides
 *   6) Template literals (`${...}`)  -> recursive resolve of every slot
 *   7) Inter-procedural returns      -> resolve the returned expression
 *   8) Logical `||` defaults         -> resolve either branch (over-approximates)
 *   9) `await expr`                  -> resolve the awaited expression
 *  10) Variable reads (SSA)          -> resolve the assigned value
 *  11) `this.foo` property reads     -> resolve the matching assignment
 *  12) Fallback                      -> wrap the raw text in `{...}` so it's
 *                                       obviously unresolved in output.
 *
 * WHY A FALLBACK:
 *   ROSDiscover returns the top value (⊤) for expressions it cannot resolve.
 *   We do the same via the `{...}` wrapper. This keeps results usable even
 *   when the resolver gives up, instead of returning no row.
 */
string resolveExprValue(Expr e) {
  // Rule 1: literal strings resolve to themselves.
  result = e.(StringLiteral).getValue()
  or
  // Rule 2: `configService.get("KEY")` becomes the placeholder `{KEY}`.
  // WHY a placeholder and not the concrete URL: the composition stage is
  // responsible for mapping env-var names to concrete services/endpoints,
  // exactly as ROSDiscover binds ROS params later via launch files.
  exists(MethodCallExpr mc |
    mc = e and
    mc.getMethodName() = "get" and
    result = "{" + mc.getAnArgument().(StringLiteral).getValue() + "}"
  )
  or
  // Rule 3: numeric literal -> decimal string.
  exists(NumberLiteral nl |
    nl = e and
    result = nl.getValue()
  )
  or
  // Rule 4: pure numeric addition (only numeric operands).
  // Handled separately from string concat to avoid "1" + "2" = "3".
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
  // Rule 5: string concatenation (at least one string/template operand).
  exists(AddExpr add |
    add = e and
    exists(Expr operand |
      operand = add.getAnOperand() and
      (operand instanceof StringLiteral or operand instanceof TemplateLiteral)
    ) and
    result = resolveExprValue(add.getLeftOperand()) + resolveExprValue(add.getRightOperand())
  )
  or
  // Rule 6: template literals - walk every element.
  exists(TemplateLiteral tl |
    tl = e and
    result = resolveTemplateElements(tl, 0)
  )
  or
  // Rule 7a: inter-procedural return via a `const f = () => ...` binding.
  exists(CallExpr call, Function f |
    call = e and
    f = call.getCallee().(VarAccess).getVariable().getAnAssignedExpr() and
    result = resolveExprValue(f.getAReturnStmt().getExpr())
  )
  or
  // Rule 7b: inter-procedural return via `function name() { ... }`.
  exists(CallExpr call, FunctionDeclStmt f |
    call = e and
    f.getName() = call.getCalleeName() and
    result = resolveExprValue(f.getAReturnStmt().getExpr())
  )
  or
  // Rule 8: `a || b` defaults - over-approximate by resolving either side.
  // WHY over-approximate: we would rather produce both URLs and let the
  // rule checker flag the divergence than silently pick one.
  exists(LogicalBinaryExpr log |
    log = e and
    (result = resolveExprValue(log.getLeftOperand()) or
     result = resolveExprValue(log.getRightOperand()))
  )
  or
  // Rule 9: `await` - unwrap the promise expression.
  exists(AwaitExpr await |
    await = e and
    result = resolveExprValue(await.getOperand())
  )
  or
  // Rule 10: variable access - resolve via SSA back to the original RHS.
  exists(VarAccess va, Expr source |
    va = e and
    DataFlow::localFlowStep*(DataFlow::valueNode(source), DataFlow::valueNode(va)) and
    not source instanceof VarAccess and
    result = resolveExprValue(source)
  )
  or
  // Rule 11: `this.foo` reads - find the matching `this.foo = ...` assignment
  // in the same class (NestJS constructors stash config into fields).
  exists(PropAccess pa, AssignExpr assign |
    pa = e and
    pa.getBase() instanceof ThisExpr and
    assign.getLhs().(PropAccess).getPropertyName() = pa.getPropertyName() and
    assign.getLhs().(PropAccess).getBase() instanceof ThisExpr and
    result = resolveExprValue(assign.getRhs())
  )
  or
  // Rule 12: fallback - wrap unresolved expressions in `{...}` so they're
  // visible in output. The guard list prevents double-handling cases that
  // any of the rules above already cover.
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
 * Resolves a template literal by concatenating its elements.
 * Kept separate from `resolveExprValue` because template literals have
 * positional children that need index-based walking.
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
 * Resolves a dataflow sink node to its canonical string, either directly or
 * via backward flow to a source that is easier to resolve.
 *
 * WHY: Some sinks are variable reads whose literal definition lives in a
 * different function; following local flow one step back often lands on a
 * template literal or literal we can resolve cleanly.
 */
string resolveUrlAtSink(DataFlow::Node sink) {
  exists(Expr e | e = sink.asExpr() and result = resolveExprValue(e))
  or
  exists(DataFlow::Node source |
    DataFlow::localFlowStep+(source, sink) and
    result = resolveExprValue(source.asExpr())
  )
}
