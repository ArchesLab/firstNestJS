/**
 * @name NestJS Axios Reconstructor
 * @kind table
 */

import javascript

/**
 * Recursive predicate to reconstruct string values, now bridging class properties.
 * Returns empty string for unresolvable expressions instead of failing.
 */
string getAPossibleValue(DataFlow::Node node) {
  // 1. Base Case: Literals
  result = node.asExpr().(StringLiteral).getValue()
  or
  // 1b. Fix: Use NumberLiteral instead of NumericLiteral
  result = node.asExpr().(NumberLiteral).getValue()
  or
  // 2. Base Case: ConfigService.get('...') because it can't jump between files
  exists(MethodCallExpr mc |
    mc.getMethodName() = "get" and
    result = "{" + mc.getAnArgument().(StringLiteral).getValue() + "}" and
    node.asExpr() = mc
  )
  or
  // 3. The Bridge: Handle 'this.notificationsBaseUrl'
  exists(PropAccess read, AssignExpr assign, PropAccess write |
    read = node.asExpr() and
    read.getBase() instanceof ThisExpr and
    // Find where this property was assigned
    write = assign.getLhs() and
    write.getBase() instanceof ThisExpr and
    write.getPropertyName() = read.getPropertyName() and
    result = getAPossibleValue(DataFlow::valueNode(assign.getRhs()))
  )
  or
  // 4. Template Literals - with fallback for unresolvable parts
  exists(TemplateLiteral tl |
    tl = node.asExpr() and
    result = getTemplateWithFallback(tl, 0)
  )
  or
  // 4b. Arithmetic (Math only)
  // exists(BinaryExpr be, float left, float right |
  //   be = node.asExpr() and
  //   be.getOperator() = "+" and
  //   // Directly check if operands are numbers without calling getAPossibleValue recursively for strings
  //   left = be.getLeftOperand().(NumberLiteral).getValue().toFloat() and
  //   right = be.getRightOperand().(NumberLiteral).getValue().toFloat() and
  //   result = (left + right).toString()
  // )
  //or
  // 4b. Smart Arithmetic (Handles 8010)
  exists(BinaryExpr add, string leftStr, string rightStr |
    add = node.asExpr() and
    add.getOperator() = "+" and
    leftStr = getAPossibleValue(DataFlow::valueNode(add.getLeftOperand())) and
    rightStr = getAPossibleValue(DataFlow::valueNode(add.getRightOperand())) and
    (
      if leftStr.regexpMatch("\\d+") and rightStr.regexpMatch("\\d+")
      then 
        // If both look like numbers, do real math
        result = (leftStr.toFloat() + rightStr.toFloat()).toString()
      else 
        // Otherwise, concatenate
        result = leftStr + rightStr
    )
  )
  or
  // 4d. Loop/Append assignment (+=) - Fixes the Loop issue
  exists(AssignAddExpr aa |
    aa = node.asExpr() and
    // In JS library, AssignAddExpr is specifically the += operator
    result = getAPossibleValue(DataFlow::valueNode(aa.getLhs())) +
             getAPossibleValue(DataFlow::valueNode(aa.getRhs()))
  )
  or
  // 5. THE LOOP FIX: Handle 'loopedUrl += "/path"' (Fixes Case 4)
  exists(AssignAddExpr aa |
    aa = node.asExpr() and
    result = getAPossibleValue(DataFlow::valueNode(aa.getLhs())) + 
             getAPossibleValue(DataFlow::valueNode(aa.getRhs()))
  )
  or
  // 6. Data Flow
  exists(DataFlow::Node source |
    source != node and
    DataFlow::localFlowStep(source, node) and
    result = getAPossibleValue(source)
  )
}

/**
 * Helper for Template Literals with fallback - handles unresolvable variables
 * Does NOT call getAPossibleValue to avoid circular recursion
 */
string getTemplateWithFallback(TemplateLiteral tl, int i) {
  i = tl.getNumElement() and result = ""
  or
  exists(string head, string tail |
    i < tl.getNumElement() and
    tail = getTemplateWithFallback(tl, i + 1) and
    (
      // Static text parts
      exists(TemplateElement te | te = tl.getElement(i) | head = te.getRawValue())
      or
      // Try to recursively resolve any expression through getAPossibleValue
      head = getAPossibleValue(DataFlow::valueNode(tl.getElement(i)))
      or
      // Fallback for identifiers that can't be resolved - use the name wrapped
      exists(Identifier id | id = tl.getElement(i) | head = "{" + id.getName() + "}")
      or
      // Fallback for property access that can't be resolved - extract property name
      exists(PropAccess pa | pa = tl.getElement(i) | head = "{" + pa.getPropertyName() + "}")
      or
      // Fallback for other unresolvable expressions - use placeholder
      exists(Expr e | 
        e = tl.getElement(i) and 
        not e instanceof Identifier and 
        not e instanceof PropAccess | 
        head = "{...}"
      )
    ) and
    result = head + tail
  )
}

from MethodCallExpr axiosCall, DataFlow::Node sink, string url
where
  axiosCall.getReceiver().(Identifier).getName().matches("%axios%") and
  (
    // Try to get first argument (handles most cases including generic <T>)
    sink = DataFlow::valueNode(axiosCall.getArgument(0))
    or
    // Fallback: if getArgument(0) fails, try through the arguments
    exists(int i | i = 0 and sink = DataFlow::valueNode(axiosCall.getArgument(i)))
  ) and
  url = getAPossibleValue(sink)
select 
  axiosCall.getLocation(),  
  axiosCall.toString(),
  "Final URL: " + url
