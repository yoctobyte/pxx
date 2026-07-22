---
track: N
prio: 55
type: bug
---

# NilPy: a list passed to a method truncates its pointer to 32-bit (SIGSEGV)

## Symptom

uforth's localstest.fth SIGSEGVs at the first `{: :}` local declaration:
`: LT0 {: :} ; 0 LT0` crashes. Backtrace:

```
#0 TPyList.count (Self=0xffffffffb212d9c0) at uforth.py:1102
#1 _define_local_names at uforth.py:752   (`for name in names:`)
```

`Self=0xffffffffb212d9c0` — the high 32 bits are all 1s: a 64-bit list pointer
was loaded/stored through a **32-bit sign-extending** path (`movslq`), so
`len(names)`/iteration dereferences a truncated wild pointer. The classic
pointer-width landmine, here on a TPyList value.

`names = list(args) + list(vals)` in `_compile_local_decl`, passed to
`_define_local_names(names)`. The list built by `list(a) + list(b)` (or the
method-argument marshalling of it) narrows the handle to 32 bits.

## Likely locus

A tyClass/list value moved through a slot typed 4-byte (tyInteger) somewhere in
the call `_define_local_names(names)` — either the parameter's frame slot, or a
`list(x) + list(y)` concat result stored to a 4-byte local. Same family as the
untyped-nested-def-param-is-tyInteger note (32-bit) in
project_promotable_int_stages123, and the variant-slot width landmines.
Reproduce by narrowing `list(a)+list(b)` passed to a def parameter.

## Impact

Blocks the locals conformance set (localstest.fth). Sets already passing:
core / coreplus / coreext / block / double / exception / facility.

## 2026-07-22: SIGSEGV FIXED (list concat); local-READ is a follow-on

FIXED (commit 040d94df): the crash was `names = list(a) + list(b)` — `+` on
two lists fell through to integer addition, so an int was passed where a list
was expected and the handle truncated. Added pylist_concat + a `+` arm.
`{: :}`, `{: A :}` (declare-only) now work.

REMAINING (follow-on): READING a local still errors — `: LT5 {: A :} A ; 5
LT5` raises a uforth-level exception (empty message, "Script error"), not a
segfault. `LocalGet` executes `frame.local_slots[token.slot]`; the compiled
NilPy reads `token.slot` off a variant-held LocalGet dataclass. Likely the
slot attribute or the local_slots index is mis-read. Declare-only locals pass;
only the read/`TO` path fails. Localstest lines up to 54 pass.

## local-READ narrowed: LocalGet never executes

Instrumenting the compiled uforth: for `: LT5 {: A :} A ; 5 LT5`, LocalInit
runs to completion (base=0, extend→1 slot, pops 5 into slot 0), but the
following `LocalGet(0)` branch NEVER fires — the run loop leaves the word
before reaching it, then main() reports an empty-message "Script error". So
either (a) `A` in the colon body did NOT compile to LocalGet (compile_token's
`_lookup_local_slot('A')` missed the freshly-declared local), or (b) the run
loop's token advance after LocalInit's `continue` desyncs. Next: dump LT5's
compiled body tokens to see whether `A` became LocalGet or an
exec_token_runtime('A') / WordCall. Declare-only locals ({: A :}, {: :}) are
unaffected; only reading/`TO` fails.
