---
prio: 70
track: A
status: done
owner: frankA
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:test/test_asm_emit_x64.pas red at 94492d162332 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T12:18:06Z
- **Test source:** test/test_asm_emit_x64.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:test/test_asm_emit_x64.pas'` at 94492d162332c9dc40bc84b11d1ae8bc467d7c6c

## Range
> **The named sha `94492d162332` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `94492d162332`, last good `3fd296c6b38d`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:1040: error: undefined variable (LibcSyscallCallCount)
pascal26:1052: error: undefined variable (PxxDbgWants)
pascal26:1075: error: undefined variable (PxxDbgWants)
(tail)
pascal26:1040: error: undefined variable (LibcSyscallCallCount)
  in: compiler/asmtext.inc
  near:  FixCount  s0  LibcSyscallCallCount >>>  AsmTextLine  
pascal26:1052: error: undefined variable (PxxDbgWants)
  in: compiler/asmtext.inc
  near: AsmMemoPoison    if PxxDbgWants >>>  a.asmmemo  
pascal26:1075: error: undefined variable (PxxDbgWants)
  in: compiler/asmtext.inc
  near: AsmMemoReport  begin if not PxxDbgWants >>>  a.asmmemo  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Re-laned P -> A: the defect is an include-visibility problem in a core file (2026-08-30)

`track: P` was **guessed from the test path** (`test/test_asm_emit_x64.pas`), which
the auto-filer marks as a guess. It is wrong. The failure is:

```
pascal26:1052: error: undefined variable (PxxDbgWants)
  in: compiler/asmtext.inc
pascal26:1075: error: undefined variable (PxxDbgWants)
```

`PxxDbgWants` is declared at **`compiler/defs.inc:5339`** and called at
**`compiler/asmtext.inc:1052` and `:1075`** (`'a.asmmemo'`). `asmtext.inc` is
pulled at `compiler.pas:113`. Nothing about this is the Pascal frontend — it is
core include structure, Track **A**.

Note the shape before assuming it is a missing forward: the same symbol is called
from `lexer.inc` (:143, :162, :299, :2977) and `dbg_filetable.inc` (:130, :228)
**without** complaint, so whatever makes it invisible is specific to how
`asmtext.inc` is reached in *this test's* configuration rather than to the
declaration being absent. **Find out which before adding a forward** — a forward
added to silence a visibility difference hides the reason the configuration
differs, and this file family has already produced three wrong mechanisms today
from reading rather than measuring.

Surfaced by frankwasm while confirming an unrelated tstate RED was not its own.
Still red; unclaimed.


---

# FIXED — 2026-08-30, frankA. It is harness rot, not include visibility.

Compiler: self-host fixedpoint `0825ad27809f`, `converged after 1 round(s)`.

## The re-laning to A was right; the mechanism was not

`asmtext.inc` is not reached differently in "this test's configuration" through
any subtlety of include order. **`test/test_asm_emit_x64.pas` is a standalone
harness that supplies its own environment instead of including `defs.inc` at
all** — that is the whole design, and the whole difference.

The question the ticket told me to answer before adding a forward — *why here
and not from `lexer.inc`* — has an exact, measured answer:

| symbol | including configurations |
| --- | --- |
| `asmtext.inc` | `compiler.pas:113` (has `defs.inc`) **and this harness (does not)** |
| `lexer.inc` | `compiler.pas:63`, and `test/manual/test_pylexer.pas` — which includes `compiler/defs.inc` at **line 9**, before `lexer.inc` at line 10 |

So `lexer.inc` "never complains" because its only standalone harness *does*
include `defs.inc`. `asmtext.inc`'s does not. Nothing is invisible; the
declaration was never in scope in that configuration and never had been.

**A forward declaration would have been the wrong fix, exactly as warned** — it
would have papered over a harness missing two pieces of the environment it
deliberately owns.

## What actually changed under it

The `a.asmmemo` memoisation (`asmtext.inc:1040-1076`) grew two references into
`defs.inc`: `LibcSyscallCallCount` (the memo poisons an entry when emitting a
line moves a counter) and `PxxDbgWants` (the PXXDBG channel selector, two sites).
Both are legitimate; the harness simply never gained them.

## Fix

Two mocks in the harness prelude, beside the ~15 it already has:

- `LibcSyscallCallCount: Integer = 0` — nothing here lowers a libc syscall, so
  0 is the honest value and the poison check correctly never fires.
- `PxxDbgWants(...) = False` — this harness asserts exact byte sequences, so a
  debug line on stdout would be noise inside the thing being measured.

## Measured both directions, and across all five harnesses

```
before:  3 undefined-variable errors  (1040 LibcSyscallCallCount, 1052/1075 PxxDbgWants)
after:   0 errors, ALL X64 ASM EMIT TESTS PASSED
```

Then every sibling, run exactly as the `test-asm` recipe does (compile, then
compare the last line against the expected banner):

```
x64    PASS      386    PASS      a64    PASS      arm32  PASS      rv32   PASS
```

`386` and `rv32` were never exposed: `test_asm_emit_386.pas` includes
`asmtext_386.inc`, a different file. Checked rather than assumed, because "the
sibling is green" is only evidence if the sibling could have been red.

## This is a recurrence, and the Makefile already says so

The `test-asm` recipe carries this comment:

> *"They ran nowhere, and four of them had stopped COMPILING: the emitters grew
> `Asm<arch>ProcessInlineLine` after the harnesses were written, and the mock
> environment never gained the line pool it reads. That is the cost of an unwired
> test exactly — it does not fail, it rots, and it rots silently."*

`compiler/rel8.inc`'s header records the same failure a third time
(`test_asm_emit_rv32.pas` rotting on an `AIntToStr` call), and is why that file
was carved out to need five mocks instead of thirty.

**The difference this time is that it did not rot silently — it went red.** The
harnesses are wired now, so the loop is closed and the cost is one prelude edit
per new reference. Not folded into a shared prelude here; that is
[[idea-a-fold-the-asm-emit-harness-mock-preludes-into-one]], which this is a
fourth data point for.

Gate: no compiler source touched — a test-only change. `make compiler/pascal26`
converged (1 round, `0825ad27809f`); all five asm-emit harnesses compile and
print their banners.
- 2026-08-30 — resolved, commit d0a2f5a72.
