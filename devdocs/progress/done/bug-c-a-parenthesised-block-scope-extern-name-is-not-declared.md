---
track: C
tags: [c, declarations, scope, rump, netbsd, link-set]
prio: 10
type: bug
blocked-by: []
summary: "`extern T * const (name)[];` inside a function (NetBSD's __link_set_decl) was never hoisted, because any `(` marked the declaration as a function declarator. A plain case errored 'undeclared identifier'; rump's prop_kern_init compiled with both link-set bounds read as 0, initialised no pool, and the pxx-built rumpnic panicked in pool_get. A lone `( ident )` is now a grouping."
status: done
owner: claude-dupwt
---

# A parenthesised block-scope extern name is not declared

NetBSD declares a link set's bounds inside the function that walks it:

    __link_set_decl(prop_linkpools, struct prop_pool_init);
    -> extern struct prop_pool_init * const (__start_link_set_prop_linkpools)[] ...;

The name is in parentheses. `CHoistBlockScopeExterns` set `hasParen` on any
`(`, to leave function declarators to the prototype path. It only took an
ident directly before `;`, `[` or `,` as the name. So the declaration was not
hoisted.

- `int f(void) { extern int (v)[]; return v[1]; }` errored "undeclared identifier".
- In rump's `prop_kern.c` it compiled, but `prop_kern_init`'s loop compared
  0 < 0 and emitted no `__start_`/`__stop_` references. No proplib pool was
  initialised. The first `prop_dictionary_create` (config_attach of a device)
  hit `KASSERT(pp->pr_itemsperpage != 0)`. That broke the pxx-built rumpnic
  under Rainyday, and also a plain host process linking the device archives.

## Fix

In the hoist's declarator scan, `( ident )` followed by `;`, `[` or `,` is
the declarator name and does not count as a function parenthesis.

## Proof

`test/c_block_extern_paren_name.c`: the NetBSD link-set shape (hidden start,
weak hidden stop, a `.hidden` asm between them) plus `extern int (plain_v);`.
The gcc main puts two entries in the section. It prints 42 (row c_bextp26).
