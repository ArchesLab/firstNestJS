/**
 * @name Axios URL Reconstructor (with Config Service)
 * @kind table
 * @id js/research/axios-url-reconstructor-config
 */

import javascript

/**
 * Recursive predicate to reconstruct possible string values.
 */
string getAPossibleValue(DataFlow::Node node) {
  // 1. Base Case: Standard String Literals
  result = node.asExpr().(StringLiteral).getValue()
  or
  // 2. NEW BASE CASE: Capture the "earliest call" to configService.get
  // This turns: configService.get('NOTIFICATIONS_SERVICE_URL') -> "{NOTIFICATIONS_SERVICE_URL}"
  exists(MethodCallExpr mc |
    mc.getMethodName() = "get" and
    (
      // Match the argument of the get call
      exists(string key | 
        key = mc.getAnArgument().(StringLiteral).getValue() and
        result = "{" + key + "}"
      )
    ) and
    node.asExpr() = mc
  )
  or
  // 3. Template Literals
  exists(TemplateLiteral tl |
    tl = node.asExpr() and
    result = getTemplateRecursive(tl, 0)
  )
  or
  // 4. Concatenation
  exists(BinaryExpr add |
    add = node.asExpr() and
    add.getOperator() = "+" and
    result = getAPossibleValue(DataFlow::valueNode(add.getLeftOperand())) + 
             getAPossibleValue(DataFlow::valueNode(add.getRightOperand()))
  )
  or
  // 5. Data Flow: Follow variables back to assignments
  exists(DataFlow::Node source |
    source != node and
    DataFlow::localFlowStep(source, node) and
    result = getAPossibleValue(source)
  )
}

/**
 * Helper: Strictly positive recursion for Template Literals.
 */
string getTemplateRecursive(TemplateLiteral tl, int i) {
  i = tl.getNumElement() and result = ""
  or
  exists(string head, string tail |
    i < tl.getNumElement() and
    tail = getTemplateRecursive(tl, i + 1) and
    (
      exists(TemplateElement te | te = tl.getElement(i) | head = te.getRawValue())
      or
      head = getAPossibleValue(DataFlow::valueNode(tl.getElement(i)))
    ) and
    result = head + tail
  )
}

from MethodCallExpr axiosCall, DataFlow::Node sink, string reconstructedUrl
where
  (axiosCall.getReceiver().(Identifier).getName() = "axios" or axiosCall.getCalleeName() = "axios") and
  sink = DataFlow::valueNode(axiosCall.getAnArgument()) and
  reconstructedUrl = getAPossibleValue(sink)
select 
  axiosCall, 
  "URL: " + reconstructedUrl