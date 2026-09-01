---
prio: 45
track: S
---

# xtensa links no program that reaches the heap runtime: `calloc` is external

- **Type:** bug — Track S (ESP), file lane A (`compiler/**`)
- **Status:** backlog, diagnosed not attempted
- **Opened:** 2026-09-01 (frankB, found while sweeping the caught-exception leak)

## Summary

**RENAMED 2026-09-01** (was `bug-s-exceptions-do-not-link-on-xtensa-the-raise-
runtime-pulls-calloc`). The original slug was measured from ONE program and
named the wrong cause: I had only tried exceptions, so "the raise runtime" was
the narrowest true statement I could make and it read as the finding. A program
with NO exceptions at all — a record holding `array of AnsiString`, nothing
else — fails identically. The common factor is the HEAP runtime, not `raise`.
Renamed rather than edited in place because the slug is what routes this.

Any program that reaches the heap runtime fails to build for `--target=xtensa`:

```
$ ./compiler/pascal26 --target=xtensa test/test_cross_exception.pas /tmp/xt
pascal26:1: error: target xtensa: external (dynamic) symbols are not supported
on this target (first one: calloc); this backend emits no dynamic segment, so
link the dependency in statically or build for a target that has one
```

So this is not one feature missing on the PRIMARY ESP target — it is anything
that allocates. Two independent programs, sharing no language feature:

- `test/test_cross_exception.pas` — raises plain Integers, no classes, no
  SysUtils. Fails.
- `test/test_managed_dynarray_field_leaks.pas` — dynamic arrays and records, no
  exceptions anywhere. Fails with the identical message.

Whatever the real dependency is, both reach it, and neither is about `raise`.

## What is measured, and what is not

MEASURED: the failure reproduces on the CLEAN TREE compiler (sha `6753ea9e5ff5`,
built from HEAD with no local changes), so it predates `620989250` and is not
caused by the exception-object leak fix. I checked this specifically because
that fix adds a `PXXObjFree` call to every handler and the obvious suspicion was
that it dragged the heap in. It did not: x86-64 code size is byte-identical
before and after (65304B), i386 likewise (106348B), so the heap was already
linked in every program that has a handler.

NOT MEASURED: which symbol in the raise path actually reaches `calloc`. The
error names only the first external symbol, and "first" is an ordering fact
about the emitter, not a root cause — the real dependency may be several calls
deep, and there may be more than one. Do not treat `calloc` as the finding.

NOT MEASURED: whether riscv32 (the other ESP target) has the same gap. It builds
and runs `test_cross_exception.pas` fine under qemu, so at minimum the two ESP
targets differ here, and that difference is itself the lead — riscv32's exception
path evidently reaches no external allocator, and whatever it does instead is
probably what xtensa should do.

## Why this is prio 45 and not higher

It blocks no umbrella that has been attempted. It is ranked here because it is a
whole-feature hole on the primary ESP target rather than a shape gap, and
because `devdocs/dev/the-goal-cross-cross.md` wants real programs on non-Linux
targets — a real program that cannot use `try/except` is a narrow kind of real.

Raise it the moment an ESP umbrella actually attempts something that raises.

## Consequences today

- `test/test_exception_object_leaks.pas` has no xtensa row, and neither does
  `test/test_cross_exception.pas`. That is correct, not an oversight: a row
  cannot be written for a target where the feature does not link. Recorded in
  the Makefile beside the rows so a later reader does not "fix" the omission.
- Any xtensa coverage claim for exception handling is vacuous today.

## First step for whoever takes it

Find what actually pulls `calloc` — do not assume. Build the same program for
riscv32 and xtensa and diff the external-symbol sets; the riscv32 path is the
working oracle sitting right beside the broken one.
