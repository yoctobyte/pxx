---
slug: bug-a-three-targets-refuse-a-shortstring-sysopen-path-four-implement-it
track: A
prio: 30
type: bug
status: open
blocked-by: []
created: 2026-09-05
found-by: frankS (closing bug-a-riscv32-and-xtensa-accept-a-shortstring-sysopen-path-and-open-nothing)
summary: "`SysOpen(sp, 0)` with `sp: ShortString` works on x86-64, riscv32 and xtensa, and is refused by name on i386, aarch64 and arm32 (`target <arch>: SysOpen expects a managed AnsiString path`). One accepted source shape, two answers, split by target. The refusals are now ASSERTED in test-core so the split cannot drift silently — that is the containment, not the fix. Deciding whether to grow the arm needs someone to want it: nothing in the tree passes a ShortString path today."
---

# Three targets refuse a ShortString SysOpen path; three implement it

## Measured

2026-09-05, compiler `0d8884ee2e9a` at `95c84cadf`, one source
(`test/test_sysopen_shortstring_path.pas`), seven targets:

| target | behaviour |
| --- | --- |
| x86-64 | works |
| riscv32 | works (local qemu RUN; fixed 2026-09-05) |
| xtensa | works (local qemu RUN; fixed 2026-09-05) |
| i386 | `error: target i386: SysOpen expects a managed AnsiString path` |
| aarch64 | `error: target aarch64: ...` |
| arm32 | `error: target arm32: ...` |
| wasm32 | **cannot build this test at all**, for an unrelated reason — a raw
  syscall in `sysutils` (`__pxxrawsyscall(SYS_getgid, ...)`). Its position on
  the ShortString question is UNMEASURED, and an earlier note claiming wasm32
  "would implement it" was never run. |

## Why this is filed rather than fixed

The refusal is a diagnostic, not a wrong answer, and CLAUDE.md defers a
differing diagnostic. What makes it a ticket anyway is
`normalise-dont-special-case.md`: one construct reachable on some targets and
refused on others is the shape where the refused arm is the one that stays
broken — and riscv32 and xtensa are the proof, because they had already made
the transition from "refuses" to "silently answers wrong" and nobody noticed
for as long as nothing asserted them.

## What landed instead

`test-core` now asserts each of the three refusals BY MESSAGE. A target that
grows the arm has to edit that row deliberately; a target that loses the refusal
and starts miscompiling goes red. This does not decide the question — it makes
the answer observable while it stays undecided.

## What would settle it

Real source that wants a ShortString path. There is none in the tree today,
which is why this is prio 30 and not higher. The implementation is not the hard
part — the three backends already own `EmitLoadStrLen*` / `EmitLeaStrData*` /
`EmitSlotAddr*` over a shared `FrozenStrPrefixSize`, so the arm adds no new
layout decision, exactly as it did not on riscv32 and xtensa. See
`SysPathFrozenSym` (`compiler/symtab.inc`) for the shared discriminator; the
per-backend part is six instructions.

Related: `bug-a-an-indexed-shortstring-sysopen-path-segfaults-on-x86-64`, which
is the same "address comes from the symbol, not from the lvalue the parser
built" root cause seen from the other side.
