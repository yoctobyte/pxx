---
track: A
prio: 78
type: feature
---

# Umbrella: make pxx programs (and the compiler) DEBUGGABLE

## The case

We are at the point where the bugs left are not "it crashes on line 12". They
are ownership bugs, truthiness bugs and type-tagging bugs whose symptom is a
**plausible wrong value far from the cause**. The current toolkit — insert
`print`, recompile, bisect the Python by hand, symbolise a crash address through
the emitted `.map` — scales badly against exactly that shape. Three concrete
data points from the songformatter campaign, all in the same week:

| bug | what the symptom looked like | what it cost |
| --- | --- | --- |
| [[bug-nilpy-slice-of-variant-local-returned-is-unusable]] | `len(self.evidence)` = `1751084129` (ASCII bytes as an int) | 3 sessions, 2 reverted fixes, a wrong root-cause premise recorded in the ticket |
| [[bug-nilpy-not-on-object-always-true]] | correct-looking key analysis with the WRONG keys, no error | only found by diffing a probe against CPython field by field |
| [[bug-nilpy-def-value-in-a-variable-is-not-callable]] | SIGSEGV with no diagnostic | jump to a `{Code,Recv}` pair read as code |

None of those three is hard once seen. Every one of them was expensive to SEE.

Ordered cheapest-first, because the cheap ones would have caught the expensive
bugs and the expensive one would not have caught the cheap ones.

## Children

### 1. [[feature-heap-poison-and-object-trace]] — runtime lib only, ~50 lines
`PXX_HEAP_DEBUG` (poison freed blocks with `$DD`, quarantine before reuse) and
`PXX_OBJTRACE` (log every retain/release/free with the address and refcount).
Turns a use-after-free from "why is this number weird" into "this is `$DDDD…`"
and turns "who owns this?" from inference into a log. Highest value/effort ratio
on the list; would have collapsed bug 1 above into a single run.

### 2. Compiler-side debug switch — `PXXDBG=<topics>`
There is **no `GetEnv` in the compiler at all** today. Every parser/typing probe
therefore costs edit-source + self-compile (~90s) + remember to strip it, which
is exactly how a wrong premise ends up in a ticket. Topics: `locals` (the
PyLocals table after `PyCollectLocalsAST`), `ctorargs` (each `PyClassCreate`
slot's AST kind and type), `ir:<proc>` (the IR for one routine), `ast:<proc>`.
Keep it a plain topic-substring test, not a registry.

### 3. DWARF that a real debugger accepts — LARGELY DONE (2026-07-29)

**The framing here was written without measuring, and two of its claims were
wrong.** Corrected against real gdb:

- *"stepping at `-O2` needs is_stmt / discriminator handling"* — **wrong**.
  `-g` only forces `-O0` when no `-O` is given, so `-g -O2` already works:
  breakpoints, correct lines, args, locals and stepping all verified at `-O2`.
- *"locals and parameters need correct frame-base expressions"* — **already
  worked** for Pascal. `break`, `bt`, `info args`, `info locals`, `next`,
  `finish` and expression evaluation were all fine before this session.

What was ACTUALLY missing, found by running gdb instead of reasoning about it:

- **NilPy had no debug info at all.** `break combine` answered "Function not
  defined". Three causes: `DbgMainTokEnd` was never set on the NilPy path (so
  every appended RTL token stamped its own line — a 19-line `.py` reported line
  5754 on every frame); `ProcBodyEnd`/`ProcDbgMain` were set only in
  `parser.inc`, so no def/method/lambda got a `DW_TAG_subprogram`; and the main
  module body is compiled inline in `ParsePyProgram`, needing its own body
  range and globals snapshot. Fixed — `58937b717`.
- **Strings and classes degraded to `void*`.** A managed string is now the
  `^Char` it really is (so gdb prints the text), and a class is a pointer to
  the same `structure_type` a record emits, so `print n.name` works. This
  improved PASCAL debugging too. Fixed — `58937b717`.
- **Variants printed as `0x6`** — the tag misread as a pointer, which *looks
  like an address*, i.e. worse than no answer. Now a real `{VType, Payload}`
  structure_type.
- **`tools/pxx-gdb.py`** ships: Variant decoding and `pxxrc EXPR`, which reads
  the refcount at `[inst-16]` — below the pointer gdb shows you, hence
  previously invisible, and half of every bug in this family.

Remaining (full list in `devdocs/dev/dwarf.md`): the line table is ONE file per
CU, so you cannot break inside an imported `.py` — the biggest gap for a
multi-module app like songformatter. Only Pascal and NilPy set `DbgMainTokEnd`;
C/Rust/Zig still have the line-number bug NilPy had (one line each in
`compiler.pas`). No `TPyList`/`TPyDict` pretty-printer yet.

The original conclusion stands and is worth keeping: we do not need to write a
debugger, we need to emit what one reads.

### 4. Debugging the COMPILER itself, not just its output
The compiler is a pxx-built binary too, so everything above applies to it — but
it also wants a `--dump-ir <proc>` / `--dump-ast <proc>` that does not require a
rebuild, and a way to run one input under a compiler built `-g` without
disturbing the pinned stable. Cheap once (2) exists.

### 5. A differential harness as a first-class tool (Track T)
Two of the three bugs above were caught by "run it under CPython and diff".
`tools/` should have that as a command, not as something each session
improvises: run a `.py` under CPython and under pxx, diff stdout, and on a
mismatch bisect the source. Track T owns the tool; findings file into the owning
lane as usual.

## Outcome (2026-07-29)

All five children landed in one campaign. What the toolkit is now, and which of
the three motivating bugs each would have caught:

| child | shipped as | would have caught |
| --- | --- | --- |
| 1 | `-dPXX_HEAP_DEBUG`, `-dPXX_OBJTRACE` | the ownership bug, in one run: `0xDDDDDDDD` instead of `1751084129` |
| 2 | `PXXDBG=<lane>.<topic>` | the wrong PREMISE — `n.ctorargs` is the probe that disproved it |
| 3 | DWARF for NilPy/C/Rust/Zig, multi-file, `tools/pxx-gdb.py` | the SIGSEGV, directly |
| 4 | `PXXDBG=a.ir:<proc>` / `a.ast:<proc>`, `make pxx-debug` | compiler-side questions, no rebuild |
| 5 | `tools/pydiff.py` | the truthiness bug — the only method that could |

The three bugs at the top of this ticket are each covered by a different tool,
which is the argument for having built all five rather than the cheapest one.

Two claims in the original text were WRONG and are corrected in child 3 below:
`-g -O2` already worked, and Pascal frame-base expressions already worked. Both
were written without measuring. The general lesson is worth keeping: the tools
that mattered were the ones that made a WRONG VALUE visible, not the ones that
made a crash easier to locate — crashes were never the expensive case.

## Order and gate

Actual order run: 1 → 3 → 2 → 5 → 4 (3 moved up once NilPy turned out to have
no debug info at all).

**Gate correction.** This said `tools/gate.sh quick`. That is WRONG for anything
touching a frontend: `--tier quick` covers ZERO C/Rust/Zig jobs, so it would
have passed the frontend DWARF work without testing a line of it. Use
`tools/gate.sh full` when the change touches a frontend or shared IR.

Every switch is OFF by default with the default path byte-identical — verified
per child, not assumed: emitted binaries compared for C, NilPy and Pascal, and
the preprocessed text compared for the C line markers. A debug facility that
changes the shipped binary is a debug facility nobody trusts.

## Log
- 2026-07-29 — resolved, commit f74df6bfb.
