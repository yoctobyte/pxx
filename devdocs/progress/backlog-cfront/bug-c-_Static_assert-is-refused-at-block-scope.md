---
summary: "`_Static_assert(sizeof(int)==4, \"...\");` inside a function body is refused with `call to undeclared function: _Static_assert` — it is in CIsTopLevelSkipIdent so the FILE-scope walk skips it, but ParseCStatementAST has no arm for it and falls through to expression parsing, where it reads as a call to an undeclared function. gcc compiles it. C11 6.7.10 allows a static assertion wherever a declaration may appear, which includes block scope. Measured 2026-09-16 identically on HEAD and on pin v410, so pre-existing and not a regression."
type: bug
track: C
prio: 30
status: backlog
created: 2026-09-16
found-by: frankb-56
tags: [c-frontend, c11]
blocked-by: []
---

# `_Static_assert` is refused at block scope

## Measured 2026-09-16

```c
int main(void){ _Static_assert(sizeof(int)==4, "int is 4"); return 0; }
```

| compiler | result |
| --- | --- |
| gcc | compiles, rc=0 |
| pxx HEAD | `pascal26:2: error: call to undeclared function: _Static_assert` |
| pxx pin v410 | identical |

**Pre-existing, not a regression** — the two readings agree, which is why it is
filed rather than fixed in the commit that found it.

## Why

`_Static_assert` is in `CIsTopLevelSkipIdent`, so the **file-scope** walk skips
it (skipping, not evaluating — the assertion is not checked there either).
`ParseCStatementAST` has no arm for it, so at block scope it reaches expression
parsing and reads as a call to an undeclared function.

Found while probing the block-scope storage-class fix
([[bug-c-a-block-scope-static-is-silently-dropped-when-a-thread-storage-class-precedes-the-type]]),
whose narrow specifier set deliberately does NOT skip `_Static_assert` —
skipping it there would have turned this loud refusal into a silent no-op,
which is worse.

## Scope

C11 6.7.10 puts a static assertion wherever a declaration may appear, which
includes block scope. Real C uses it inside functions to pin layout assumptions
next to the code that depends on them.

**Refusing is the honest failure and is not urgent** — nothing compiles wrong
today, and the message names the construct. This is a gap, not a defect in
emitted code.

## Not just parsing

Note that the file-scope path **skips** the assertion rather than evaluating it,
so a false `_Static_assert` at file scope is currently accepted silently. Fixing
block scope by skipping there too would extend that silence rather than close
it. Whoever takes this should evaluate the constant expression in both places
and refuse on a false one — that is the point of the construct, and a skipped
assertion is a guard that cannot fail.
