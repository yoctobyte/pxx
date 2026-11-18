---
track: C
tags: [c, declarations, scope, rump, netbsd]
prio: 10
type: bug
blocked-by: []
summary: "`extern struct domain arpdomain, inetdomain;` inside a function, with inetdomain already declared at file scope, left arpdomain undeclared. CHoistBlockScopeExterns checked only the LAST declarator's name. Now it hoists the list when any name is new (rump netinet_component.c)."
status: done
owner: claude-dupwt
---

# A block-scope extern list hoists only when its last name is new

Pass 2 discards a block-scope `extern` declaration, so its names resolve to
file-scope symbols. Pass 1's `CHoistBlockScopeExterns` registers a name the
file has not declared, as if written at file scope. It took the declaration's
last declarator name and hoisted only when that name was unknown. In
`extern struct domain arpdomain, inetdomain;` with `inetdomain` already in a
header, `arpdomain` was never registered, and the use errored
"undeclared identifier 'arpdomain'". The other order worked.

Found in Rainyday's rumpnic build: `sys/rump/net/lib/libnetinet/netinet_component.c`
was the one file of 468 that pxx did not compile.

## Fix

Every declarator name in the list is checked, and the declaration is hoisted
when any of them is new. Re-declaring a known extern at file scope is legal
and changes nothing.

## Proof

`test/c_block_extern_list_partly_known.c` with a gcc main defining both:
prints 42 (row c_bextl26). Rainyday's rump tree: 468/468 compile.
