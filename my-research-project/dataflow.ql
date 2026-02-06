//This query only returns axios functions with Template URL instead of actual URL
/**
 * @name Axios URL Reconstructor
 * @description Finds axios calls and reconstructs the dynamic URL strings used.
 * @kind table
 */

import javascript

/**
 * Recursive predicate to reconstruct strings.
 * We've added your specific "Source" logic as a base case.
 */
string getAPossibleValue(DataFlow::Node node) {
  // Base Case 1: Standard String Literals
  result = node.asExpr().(StringLiteral).getValue()
  or
  // Base Case 2: Your specific config getter (e.g., get("USER_SERVICE_URL"))
  exists(MethodCallExpr mc |
    mc.getMethodName() = "get" and
    mc.getAnArgument().getStringValue().toLowerCase().matches("%_service_url") and
    node.asExpr() = mc and
    result = "{" + mc.getAnArgument().getStringValue() + "}"
  )
  or
  // Concatenation: 'a' + 'b'
  exists(BinaryExpr add |
    add = node.asExpr() and
    add.getOperator() = "+" and
    result = getAPossibleValue(DataFlow::valueNode(add.getLeftOperand())) + 
             getAPossibleValue(DataFlow::valueNode(add.getRightOperand()))
  )
  or
  // Template Literals: `https://${host}/api`
  exists(TemplateLiteral tl |
    tl = node.asExpr() and
    // For simplicity, we flag that this is a template
    result = "[Template URL]" 
  )
  or
  // Branches & Data Flow: Trace back to previous assignments
  exists(DataFlow::Node source |
    source != node and
    DataFlow::localFlowStep(source, node) and
    result = getAPossibleValue(source)
  )
}

from MethodCallExpr axiosCall, DataFlow::Node sink, string reconstructedUrl
where
  // Identify the Sink (Axios URL argument)
  axiosCall.getReceiver().(Identifier).getName() = "axios" and
  sink = DataFlow::valueNode(axiosCall.getArgument(0)) and
  
  // Apply the recursive reconstruction
  reconstructedUrl = getAPossibleValue(sink)

select 
  axiosCall, 
  "Axios " + axiosCall.getMethodName() + " uses possible URL: " + reconstructedUrl
  