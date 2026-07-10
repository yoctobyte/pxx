---
prio: 30  # auto — rare pattern, corpus doesn't hit it; recipe fully derived
---

# C: call through deref of a STRUCT-MEMBER pointer-to-function-pointer

- **Type:** bug (C frontend codegen) — **Track C** (`compiler/cparser.inc`,
  `compiler/symtab.inc`, `compiler/defs.inc`).
- **Status:** done
  [[bug-c-call-through-deref-of-fnptr-pointer]] (whose local/param/global +
  cast forms are all fixed).

## What
`struct S { ft *pf; };  (*s.pf)(args)` — a struct field that is itself a
POINTER-to-function-pointer, called through a deref. Drops the call the same way
the bare-identifier form did (CNodeProcSig strips the deref, the AN_FIELD arm's
`RecFieldProcSig` returns -1 because the field is a pointer, not a direct
fn-pointer). Direct fn-pointer fields (`ft f; s.f(args)`) already work.

Rare — no corpus target (sqlite/lua/tcc/duktape) uses this shape; that is why it
was split out rather than blocking the parent fix.

## Recipe (fully derived, not yet applied)
1. `defs.inc`: parallel field array `UFldElemProcSig[]` beside `UFldProcSig`.
2. `symtab.inc`: copy it in the field-copy loop (~575); set it from a new
   `LastTypePtrElemProcSig` global where `UFldProcSig[fi] := LastTypeProcSig`
   (~605); add `RecFieldElemProcSig(rec, field)` beside `RecFieldProcSig`.
3. `cparser.inc` struct builder: capture `CTypePtrElemProcSig` at the field
   parse (~8558, beside `fldProcSig := CTypeProcSig`) and thread it through the
   `bfProcSig`-parallel bitfield path (~8574 / ~8769 / ~8823) into
   `UFldElemProcSig`.
4. `cparser.inc` `CNodeProcSig` AN_FIELD arm (~2063): mirror the AN_IDENT arm —
   when `RecFieldProcSig` < 0 but a deref was stripped and
   `RecFieldElemProcSig >= 0`, keep ONE `AN_DEREF` as the callee and take the
   sig from the field-elem channel.

## Acceptance
- `struct S{ ft *pf; } s; ... (*s.pf)(5)` calls correctly (extend
  `test/cfnptr_deref_call_b241.c` with a struct case, exit 42).
- c-testsuite still 220/220; self-host byte-identical (C-frontend only).

## Log
- 2026-07-10 — resolved, commit 9f113aaa.
