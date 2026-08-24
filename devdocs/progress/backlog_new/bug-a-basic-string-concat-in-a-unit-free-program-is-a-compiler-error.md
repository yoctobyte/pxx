---
slug: bug-a-basic-string-concat-in-a-unit-free-program-is-a-compiler-error
title: "BASIC: `PRINT s + t` in a unit-free program is `call to a runtime stub that was never emitted`"
track: A
prio: 35
type: bug
blocked-by: [decide-how-much-string-machinery-the-basic-frontend-gets]
status: backlog_new
owner: ""
created: 2026-08-24
summary: "Concatenating two string variables in a .bas program with no USES fails with `compiler error: call to a runtime stub that was never emitted`. The concat lowering reaches AnsiStrConcatAddr, which is 0 because the emitted AnsiString shims are not there -- and they cannot be, because every shim's body is a builtinheap procedure and BASIC pulls builtinheap only through USES. Present on pinned. The sibling of the PXXStrFromLit hole, one stub family over."
---

# Symptom

```
$ cat > c.bas <<'X'
DIM s = "abc"
DIM t = "def"
PRINT s + t
X
$ pascal26 c.bas c
pascal26:3: error: compiler error: call to a runtime stub that was never
emitted (code offset 0 is the ELF entry point). A frontend driver is missing
its stub-emission call for the current flags/target.
```

Reproduced on `pinned` as well as HEAD, so it is not a regression from the
shim-gating fix in
[[bug-a-a-unit-free-basic-program-calls-a-helper-it-never-emits]] — that fix
made a *different* stub family (`PXXStrFromLit`) honest, and this one has the
same cause one family over.

# The cause, and why it is not simply "emit the shims"

`AnsiStrConcatAddr` is 0 because `EmitAnsiStringRuntime` did not run. It cannot
usefully run for a unit-free `.bas` program: the shims are nine pushes around
`EmitCallProc(FindProc('PXXStrConcat'))`, and `PXXStrConcat`'s body ships in
**builtinheap**, which BASIC pulls through exactly one door — `USES`. Emitting
them anyway is what produced the `PXXStrFromLit` hole, where the call survived
the whole compile as an unresolved placeholder and silently did not happen.

So this needs a decision, not a patch, and it is the same one that ticket
deferred:

1. **Pull `builtinheap` when a `.bas` program does managed-string work.** Honest
   and matches every other driver (`ParseUsesUnitAmbient('builtinheap')` is what
   Pascal, C and NilPy do). Costs the unit: `10 PRINT "hello"` is 559 bytes
   today and `test_basic_comprehensive.bas`, which pulls it, is 103 KB. Gating
   on "does this source concatenate" keeps the small programs small.
2. **Give BASIC frozen-string concatenation** that does not reach the managed
   path at all. BASIC has no `A$` variables and its `DIM s = "..."` is a
   `tyString`, so the managed path may be entirely gratuitous here.

Option 2 was measured on 2026-08-24 and **does not exist**: a Pascal program
doing `ShortString + ShortString` pulls builtinheap too and comes out at 63,760
bytes. There is no frozen-string concat path that skips the unit, in any
frontend. That turns this into a size-vs-capability call rather than a coding
question, and it is now **blocked on
[[decide-how-much-string-machinery-the-basic-frontend-gets]]**, which carries
the three options, the measurements and a recommendation.

## Checked 2026-08-24: NOT the same defect as the one-char-string bug

This ticket used to say *"see
[[bug-a-basic-prints-a-string-variable-as-its-character-code]] ... settle that
one first; it may turn out this is the same defect wearing a second hat."*
It was settled, and it is **not**. With one-character initialisers now correctly
typed as strings, `PRINT s + t` still fails identically for `"abc" + "def"` and
for `"a" + "b"`. Independent bug, unchanged scope.

## ...and it has a THIRD sibling: string COMPARISON, on cross targets only

Found the same day, by the same fix. `IF a = "x"` in a unit-free `.bas` program
used to pass by accident — the variable was a tyInteger holding 120, so it was
an integer compare. Now that it is a real string compare it needs `PXXStrEq`,
and on aarch64 and arm32 that is

```
pascal26:22: error: compiler error: PXXStrEq not found
```

x86-64 and i386 compile it — they have an inline path — which is why this is
recorded here rather than filed separately: it is the same root (a
managed-string helper whose body ships only with builtinheap) reached through a
third operator, and it should be fixed by the same decision. Whichever option
above is chosen must cover `+`, `=` and `<>`, and the cross rows are what prove
it — the native tier alone would call two of the three fixed.

# Gate when it is done

The three existing `.bas` tests unchanged on x86-64 / i386 / aarch64 / arm32,
plus this program compiling AND printing `abcdef`, plus
`test/test_basic_unit_free_string_literal.bas` staying small (it asserts the
unit-free path, and pulling builtinheap unconditionally would defeat it without
failing it).
