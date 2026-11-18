/* A block-scope extern list hoists when ANY of its names is new: inetdomain
   is already declared at file scope, arpdomain is not (rump netinet_component.c).
   bug-c-a-block-scope-extern-list-hoists-only-when-its-last-name-is-new */
struct domain { int x; };
extern struct domain inetdomain;
int sum_domains(void) { extern struct domain arpdomain, inetdomain; return arpdomain.x + inetdomain.x; }
