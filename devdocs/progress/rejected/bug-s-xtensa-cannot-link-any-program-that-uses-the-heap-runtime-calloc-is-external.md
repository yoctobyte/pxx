---
prio: 45
status: rejected
track: S
blocked-by: []
summary: "REJECTED 2026-09-05: the report is false as titled, and the part that is true is deliberate. RE-MEASURED independently on compiler 5783500470d0 and every claim holds -- xtensa links AND RUNS heap programs with NO flag: --platform=posix gives `heap ok / caught boom / done` under qemu, and --esp-profile=bare builds a heap program at 45540B. What refuses is the DEFAULT (IDF) profile, on purpose: compiler.pas:311 derives xtensa to PLATFORM_ESP, where externals are the IDF link's job, and the error says so at length and names both alternatives. BLOCKED-BY EDGE REMOVED: it cited the CALL0/CALL8 forward-call wall, and f49c0e11f cleared that for ordinary programs -- the working configurations above need no flag. The slug is deliberately NOT renamed despite being false; see the note in the body."
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

## Re-measured 2026-09-05 (frankS): the title is not what happens

Run under `qemu-xtensa`, not inferred from a successful link:

| configuration | result |
| --- | --- |
| `--target=xtensa` (default = ESP) | refuses: externals not supported, first one `calloc` |
| `--target=xtensa --platform=posix` | links, **runs**, prints `heap ok` |
| `--target=xtensa --esp-profile=bare` | links, **runs** |
| exceptions, posix + `--xtensa-long-calls` | prints `caught boom / done` — identical to riscv32 |

The default derivation is deliberate (`compiler.pas:311`): xtensa goes to
`PLATFORM_ESP` because it has no hosted leg by default, and on that platform
externals are meant to be resolved by the IDF link rather than by this writer.
The error message already explains that and names both escapes.

So the residual question is not "why can't xtensa link the heap" — it can. It is
whether the default profile should be ESP when a hosted xtensa image is what the
cross suite actually runs under qemu. That is a Track U shape if anyone wants it
settled; it is not this bug.

Note the exceptions row needed `--xtensa-long-calls`, which is
[[feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image]] and is now
the `blocked-by`.


## Rejected 2026-09-05 (frankS) — re-measured, and the blocker removed

### Every claim in the summary re-verified independently

On compiler `5783500470d0`, **no `--xtensa-long-calls`**, one Pascal program
doing `GetMem`/`FreeMem` plus a full `try raise Exception … except`:

| configuration | result |
| --- | --- |
| `--target=xtensa --platform=posix` | links 651116 B; **runs**: `heap ok` / `caught boom` / `done` |
| `--target=xtensa --esp-profile=bare` | links 45540 B (heap without `sysutils`) |
| `--target=xtensa`, default profile | refuses — `external (dynamic) symbols are not supported on this target (first one: calloc)` |

The third row is the whole report, and it is **deliberate**: `compiler.pas:311`
derives xtensa to `PLATFORM_ESP`, where externals are the IDF link's job. The
error is not terse about it — it names `--platform=posix`, names
`--esp-profile=bare`, and explains that the IDF profile's externals are meant to
be resolved by the IDF link. A documented, explained, intentional refusal with
two working alternatives is not a bug.

*(An earlier attempt of mine to build the bare row failed with `unit source not
found: platform_backend`. That was my probe missing `-Fulib/rtl`, not a defect —
recorded so the next person does not read it as one.)*

### The blocked-by edge is gone, and why

It cited `feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image` as
*"the real blocker behind the configurations that do work"*. **That is no longer
true.** `f49c0e11f` reserves the wide call form unconditionally for
`FiniRunnerProc`, which was the callee every ordinary program tripped over, and
the working configurations above now build and run with **no flag at all**. The
call wall still exists for one known program — the compiler itself, on an
ordinary-proc forward call 23 MB out — but nothing on this ticket touches it.

Edge removed rather than left in place: a stale blocker is worse than none,
because it makes a takeable ticket look unavailable. This was the only ranked
item standing in `backlog-esp` behind a live blocker.

### The slug is FALSE and is deliberately not renamed

`bug-s-xtensa-cannot-link-any-program-that-uses-the-heap-runtime-calloc-is-external`
is wrong — xtensa links such programs — and it will misroute anyone who meets it
in a listing, which is most readers.

**Renaming it anyway would cost more than it saves.** The slug is the citation
key: other tickets, commits and `resolve` entries refer to it by name, and
`rejected/` is a loaded folder specifically so those citations keep resolving.
A rename breaks every existing reference to fix a name that now sits in a
terminal folder where nobody is looking for work.

So the correction lives where a reader actually lands — in the `summary`, whose
first six words are `REJECTED … the report is false as titled`. That is the line
every listing shows. **This is the same trade as putting the pin condition next
to the error string rather than in a report: fix it in the reader's field of
view, not in the index.**
