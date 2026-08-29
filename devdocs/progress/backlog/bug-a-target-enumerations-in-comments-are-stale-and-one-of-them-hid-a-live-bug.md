---
track: A
prio: 20
type: bug
status: open
found: 2026-08-29
found-by: frankD
summary: "Sweep of every comment that ENUMERATES targets, checked against a derived backend list. Three miscounts: PXXVarBinOp's 'the other four targets' (five call it), symtab.inc's 'Every 32-bit backend (i386, arm32, riscv32)' (xtensa is a fourth and does NOT consult the shared decision), and PXXStrCmp3's 'the four cross backends' — that last one already filed as a live bug. A count reads as a complete enumeration, so nobody counts."
---

# Target enumerations in comments are stale, and one of them hid a live bug

Pass 3 of [[audit-a-a-comment-asserting-an-invariant-is-a-claim-about-a-sibling-arm-nobody-checked]].
Read-only. The sweep the coordinator dispatched: **every comment containing a
target enumeration, checked against a backend list DERIVED at sweep time** — not
typed, because a sweep for miscounted enumerations that carries a hand-written
enumeration is the same defect wearing the auditor's hat.

## The derived list

```
$ grep -nE "^\s*TARGET_[A-Z0-9_]+\s*=" compiler/defs.inc   ->  7 constants
$ ls compiler/ir_codegen*.inc                              ->  6 backend files
```

**7 registered targets, 6 with a backend, 5 cross backends** (everything but
x86-64). wasm32 is registered without codegen, which is why the two numbers
differ — and is itself a trap for anyone who counts `TARGET_*` and stops.

Note the file naming does not spell the target: `ir_codegen.inc` is x86-64 and
`ir_codegen386.inc` is i386, while the other four are `ir_codegen_<arch>.inc`.
A glob for `ir_codegen_*.inc` (one underscore) silently returns **four**. That is
almost certainly where "the four cross backends" came from.

## The three miscounts

### 1. `PXXStrCmp3` — *"the four cross backends"* — **LIVE BUG, already filed**

[[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]]. Five
cross backends; the fix went to four; xtensa still compares heap handles.

### 2. `compiler/builtin/builtin.pas:1055` — *"this is the other four targets' half"*

`PXXVarBinOp`'s header, about the variant-arithmetic coercion fix. **Five cross
backends call `PXXVarBinOp`** — i386, aarch64, arm32, riscv32 **and xtensa**.

**No defect**: the fix is in the shared Pascal helper, so all five got it. The
count is simply wrong, and it is wrong in the same seam, the same direction and
the same file family as the one that *did* cost a live bug. Fix the number, or
better, stop counting: *"this is the cross backends' half"* stays true when a
sixth lands.

### 3. `compiler/symtab.inc:3333` — *"Every 32-bit backend (i386, arm32, riscv32)"*

This is the interesting one, because the comment's own thesis is what the
omission breaks. It introduces `Arg32Class`/`Arg32Words`, the shared by-value
call-argument decision, and says:

> *"A backend that consults this cannot silently lack a case: it can only fail
> loudly on a class it does not handle."*

**xtensa is a 32-bit backend and does not consult it.** `Arg32Class` and
`Arg32Words` are referenced from `ir_codegen386.inc`, `ir_codegen_arm32.inc` and
`ir_codegen_riscv32.inc` only. xtensa carries its own 64-bit argument model
(`ir_codegen_xtensa.inc:232`, *"the xtensa C ABI starts a 64-bit argument at an
EVEN word index"*, and the `Is64Pair`-style predicates at :485-505).

**I am not claiming a defect here and did not find one.** What I can state is
narrower and still worth a ticket: the consolidation that exists precisely
because *"three backends x three kinds, nine copies that were never meant to
differ — and they drifted"* covers three of the four 32-bit backends, and the
comment's "Every" hides the fourth. Whoever owns this should decide whether
xtensa joins the shared decision or is deliberately out; either way the word
"Every" needs to go, because today it tells a reader the invariant holds
everywhere it is relevant.

Worth noting the ctor-call path at `ir_codegen_xtensa.inc:1786-1796` counts every
argument as exactly one word (`Inc(nArgs)`, word *i* at `(nArgs-1-i)*4`) with no
type classification at all. There is 64-bit argument machinery elsewhere in the
file, so this may be a path that never sees a wide argument — **that is the
question to answer, and I could not answer it read-only.**

## Checked and CORRECT — recorded so nobody re-checks

- `elfwriter.inc:767` — *"the four targets that get DWARF -g (esp xtensa/riscv32
  excluded)"*. 6 backends − 2 = 4. Correct, and it shows its arithmetic.
- `pasparser_stmt.inc:5615` — *"in all six backends"*. Six backend files. Correct.
- `builtin.pas:2330` — *"hand-emitted for six targets"*. Correct.
- `symtab.inc:11820` — `DivZeroCheckProc`, *"Five backends transcribing…"*.
  Correct: x86-64 is discussed separately two lines later, so "five" is the
  cross set.
- `symtab.inc:10280` — `SciFormatFor`, *"five backends ask the same question"*.
  Correct on the same reading.

**Five correct, three wrong.** The seam is mostly sound, which is worth saying —
an audit that only records failures cannot tell anyone whether to trust the rest.

## The cheap remedy, which is the point of the ticket

Every one of the three is falsified in under a second by a command that derives
the list instead of trusting the sentence:

```
ls compiler/ir_codegen*.inc                 # 6, not 4
grep -c "^\s*TARGET_[A-Z0-9_]* =" compiler/defs.inc
```

**When you write a count of targets into a comment, run one of those first — and
prefer a phrase that does not carry a number.** "The cross backends" cannot go
stale; "the four cross backends" went stale the day xtensa landed and cost a
wrong `<` on a whole target.

### Not a tool bug — a mechanical generator of a HUMAN error

Correcting my own framing, because the wrong word would send someone hunting for
a broken tool: **nothing in `tools/**`, the Makefile or CI runs that glob.** No
machine executes `ir_codegen_*.inc` anywhere in the repo. It is a shell idiom
that returns four when the answer is six, sitting exactly where a person reaches
for a quick enumeration before writing a sentence. That is a worse category than
a tool bug and a less searchable one, but it is not a tool bug, and this ticket
should not read as though a script needs fixing.

## Gate

Comment-only for #1's count and #2; #3 is a question for A, not an edit.
`make compiler/pascal26` byte-identical.
