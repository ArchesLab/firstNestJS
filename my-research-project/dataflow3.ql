/**
 * @name NestJS Axios Reconstructor
 * @kind table
 */

import javascript

/**
 * Recursive predicate to reconstruct string values, now bridging class properties.
 */
string getAPossibleValue(DataFlow::Node node) {
  // 1. Base Case: Literals
  result = node.asExpr().(StringLiteral).getValue()
  or
  // 2. Base Case: ConfigService.get('...')
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
    // Recurse into the right-hand side of the assignment
    result = getAPossibleValue(DataFlow::valueNode(assign.getRhs()))
  )
  or
  // 4. Template Literals
  exists(TemplateLiteral tl |
    tl = node.asExpr() and
    result = getTemplateRecursive(tl, 0)
  )
  or
  // 5. Standard Local Flow (for variables like 'url' inside the method)
  exists(DataFlow::Node source |
    source != node and
    DataFlow::localFlowStep(source, node) and
    result = getAPossibleValue(source)
  )
}

/**
 * Helper for Template Literals
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

from MethodCallExpr axiosCall, DataFlow::Node sink, string url
where
  axiosCall.getReceiver().(Identifier).getName() = "axios" and
  sink = DataFlow::valueNode(axiosCall.getArgument(0)) and
  url = getAPossibleValue(sink)
select axiosCall, "Final URL: " + url