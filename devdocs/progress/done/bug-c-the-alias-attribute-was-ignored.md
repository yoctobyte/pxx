---
slug: bug-c-the-alias-attribute-was-ignored
track: C
prio: 75
type: bug
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: pxx2 (Nodisx dhcpcd recipe, compat/setproctitle.c)
tags: [cfront, objects, symbols, dce]
summary: "`__attribute__((alias(\"t\")))` was dropped: the declared name stayed an undefined import and the link failed (dhcpcd's `extern __typeof(setproctitle_impl) setproctitle __attribute__((__alias__(\"setproctitle_impl\")))`). The lexer now files the declarator just before the attribute and its target, and ParseCProgram turns them into the file-scope asm aliases the object writer already emits (.weak with `weak`, else .globl). A `static` target with no caller of its own was then deleted by DCE; alias targets are DCE roots in an object now. Test c_aliasattr26: two objects linked by pxx, against gcc (prototype, __typeof'd static target, weak, data)."
---

# The alias attribute was ignored

```c
static void setproctitle_impl(const char *fmt, ...) { ... }
extern __typeof(setproctitle_impl) setproctitle
	__attribute__((__alias__("setproctitle_impl")));
```

(libbsd's spelling, copied into dhcpcd as compat/setproctitle.c.) pxx read
the attribute and kept nothing of it, so `setproctitle` was an import in the
object, and dhcpcd's link stopped on `undefined reference to 'setproctitle'`.

## Fix

* `compiler/clexer.inc`: CAttrAliasOf finds `alias("t")` / `__alias__("t")`
  in the attribute (in the source's own case: the attribute text the other
  tests read is lower-cased). CAttrPrevDeclName takes the declarator from the
  tokens already lexed: the identifier just before, or the one before a
  parameter list or array bounds. An alias attribute anywhere else is an
  error, not a guess. They go to CLexAliasName/Target/Weak (defs.inc).
* `compiler/cparser.inc`, ParseCProgram: after it resets the file-scope asm
  tables (lexing runs first), each becomes CFsaAlias + CFsaBind, the same
  records `__asm(".globl a\na = b")` makes (feature-c-file-scope-asm-symbol-aliases),
  so the writer's checks and emission are shared.
* `compiler/dce.inc`, DceMarkAll: in an object, a proc named as an alias
  target is a root. setproctitle_impl is `static` and nothing calls it; DCE
  dropped its body and the writer then refused the alias ("not defined in
  this translation unit"). The same held for an asm alias to a static.

## Not covered

* An EXECUTABLE (no --emit-obj): aliases of either spelling are not emitted
  there; see bug-c-an-alias-in-an-executable-becomes-a-dynamic-import.
* `extern __typeof(f) g;` with no earlier prototype of g declares a variable;
  see bug-c-typeof-of-a-function-declares-a-variable. The test (and dhcpcd)
  declare the prototype first.
