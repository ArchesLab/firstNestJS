// /**
//  * @name Flow to Clubs URL
//  * @kind path-problem
//  * @id js/research/flow-to-clubs-url
//  */

// import javascript
// import semmle.javascript.dataflow.DataFlow
// import DataFlow::PathGraph // Required for visual arrows

// // Define the flow configuration
// module ClubsFlowConfig implements DataFlow::ConfigSig {
//   // 1. Where the data starts (The "Source")
//   predicate isSource(DataFlow::Node source) {
//     exists(MethodCallExpr mc |
//       mc.getMethodName() = "get" and
//       mc.getAnArgument().toString().matches("%CLUBS_SERVICE_URL%") and
//       source.asExpr() = mc
//     )
//   }

//   // 2. Where the data ends up (The "Sink")
//   predicate isSink(DataFlow::Node sink) {
//     exists(VariableDeclarator decl |
//       decl.getBindingPattern().(Identifier).getName() = "url" and
//       sink.asExpr() = decl.getInit().getAChild*()
//     )
//   }
// }

// module ClubsFlow = DataFlow::Global<ClubsFlowConfig>;

// from ClubsFlow::PathNode source, ClubsFlow::PathNode sink
// where ClubsFlow::flowPath(source, sink)
// select sink.getNode(), source, sink, "Data flows from ConfigService to this URL."
// //over 5 minutes

import javascript

// Look for the "Source" (The Config call)
query predicate foundSource(MethodCallExpr getCall) {
  getCall.getMethodName() = "get" and
  getCall.getAnArgument().toString().matches("%CLUBS_SERVICE_URL%")
}

// Look for the "Sink" (The URL variable)
query predicate foundSink(VariableDeclarator urlDecl) {
  urlDecl.getBindingPattern().(Identifier).getName() = "url"
}

from TopLevel tl
select count(MethodCallExpr m | foundSource(m)) as sources, 
       count(VariableDeclarator v | foundSink(v)) as sinks
