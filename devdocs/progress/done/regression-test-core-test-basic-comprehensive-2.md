---
prio: 70
status: done
owner: claude-A
---

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_basic_comprehensive.bas red at 7d4a3dbb99ce (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-23T23:22:22Z
- **Test source:** test/test_basic_comprehensive.bas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_basic_comprehensive.bas'` at 7d4a3dbb99ce2bc83a5fbde50a6844292c5bd21a

## Range
bad `7d4a3dbb99ce`, last good `df21e490d798`, 14 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:3906: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/target.
(tail)
pascal26:3906: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/target.
  in: /tmp/testmgr-scratch-1498618/compiler/builtin/builtinheap.pas
  near: Exit  end  end  >>> end  function 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Fixed 2026-08-24 (claude-A) — the BASIC driver never emitted the AnsiString runtime

**Cause, and it is not in the BASIC program.** `EmitAnsiStringRuntime` puts the
managed-string shims (AnsiStrFromLiteral, AnsiStrConcat, retain/release…) in the
image and fills in their `AnsiStr*Addr` code offsets. The Pascal, C and NilPy
drivers each call it. The BASIC driver never did.

A BASIC program pulls `builtinheap` as soon as anything needs the heap, and
builtinheap is Pascal: its bodies concatenate string literals, so they compile
calls to those addresses. With no emission the addresses are still 0, and
`IREmitCodeCall`'s guard turns what would otherwise be a jump to the ELF entry
point (an infinite re-entry into main until the stack is gone) into a compiler
error — reported against a line in `compiler/builtin/builtinheap.pas`, a file
the BASIC program does not mention. That is the guard working as designed;
without it this would have been a hang with a garbage backtrace.

**Why it appeared now.** Nothing about BASIC changed. `PXXVarBinOp` gained a
diagnostic string — `PXXVariantError('unsupported operator on a Variant')`, from
[[bug-a-not-on-an-integer-variant-answers-a-boolean]] — and that is the first
managed-string literal reachable in builtinheap on this path. The gap has been
latent since the driver was written; the bisect's `bad` commit is where it
became reachable, not where it was introduced.

**Fix:** the BASIC driver now makes the same call, gated on the same
`DetectPascalRuntimeNeeds` pre-scan and the same x86-64 condition the C driver
uses, with `RegisterEmittedStringRuntimeForwards` first so the emitter can
reference builtinheap bodies that have not been parsed yet.

**This is the fourth time this driver has been the one that did not make a call
every other driver makes** — after the `--threadsafe` I/O lock stubs, the signal
runtime ([[bug-a-only-the-pascal-driver-emits-the-signal-runtime]]) and the
System intrinsics (`RegisterBuiltinTGuid`/`TObject`), all three recorded in
comments within twenty lines of this one. The pattern is worth naming in the
ticket rather than fixing quietly a fourth time: a frontend driver is a
CHECKLIST that exists in five copies, and the copies drift in one direction —
whatever the Pascal driver gained last. Filed as
[[refactor-a-one-program-driver-prologue-for-every-frontend]].

Gate: `make compiler/pascal26` fixedpoint converged; all three `.bas` tests in
`test-core` pass (`test_basic_comprehensive` 21 lines, `test_basic_goto_gosub`
and `test_basic_lexer` byte-exact); `tools/gate.sh quick` GREEN.
- 2026-08-24 — resolved, commit PENDING-COMMIT.
