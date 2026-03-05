// import javascript

// from DataFlow::PropWrite pw
// where pw.getPropertyName().matches("%BaseUrl%") or
//       pw.getPropertyName().matches("%ServiceBase%") or
//       pw.getPropertyName().matches("%Url%")
// select pw, pw.getBase(), pw.getRhs()
import javascript

from DataFlow::PropWrite pw
where pw.getPropertyName().matches("%BaseUrl%") or
      pw.getPropertyName().matches("%ServiceBase%")
select pw, pw.getBase().asExpr(), pw.getBase().asExpr().getAQlClass()