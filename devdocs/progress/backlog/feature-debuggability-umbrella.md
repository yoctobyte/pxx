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

### 3. DWARF that a real debugger accepts
We already emit some DWARF (`elfwriter.inc` writes field offsets, class layout,
line info). What is missing is the level at which `gdb ./prog` is actually
useful:

- line table accurate enough to STEP (currently `-g` implies `-O0`; stepping at
  `-O2` needs is_stmt / discriminator handling)
- locals and parameters with correct frame-base expressions, so `info locals`
  and `p someVar` work
- the NilPy/Pascal type graph deep enough for `p self.evidence` to print a list
  rather than a pointer — for a managed AnsiString, a TPyList, and a Variant
  this means synthetic/pretty-printable types
- a gdb pretty-printer script shipped alongside (`pxx-gdb.py`) that knows
  `TPyVarRec` tags, `TPyList`, `TPyDict`, and the `[inst-16]` object header
  (refcount + magic) — so `p obj` shows the REFCOUNT, which is half of every
  bug in this family

With that, breakpoints, stepping, and register/memory inspection come free from
gdb and from the IDE integrations that speak DAP — we do not need to write a
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

## Order and gate

1 → 2 → 5 → 3 → 4. Each child lands independently under Track A's gate
(`tools/gate.sh quick` + self-host byte-identical), and every switch must be OFF
by default with the default path byte-identical — a debug facility that changes
the shipped binary is a debug facility nobody trusts.
