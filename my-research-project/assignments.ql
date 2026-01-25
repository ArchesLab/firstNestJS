//Run: codeql query run my-research-project\assignments.ql --database=my-db      
import javascript

from Variable v, VarAccess access, VariableDeclarator decl
where 
decl.getBindingPattern().getVariable() = v and 
v.getName() = "url" and 
exists(TemplateLiteral tl |
  tl = decl.getInit() and
  tl.toString().toLowerCase().matches("%clubsBaseUrl%")
) and
access = v.getAnAccess()
select access, "Access of variable 'url' which was initialized with clubsBaseUrl data."
