---
slug: feature-n-import-threading-should-imply-threadsafe
track: N
type: feature
prio: 55
status: working
owner: frankb-8e
created: 2026-09-10
found-by: frankB
tags: [nilpy, threading, options, upward-compat]
blocked-by: []
summary: "`import threading` compiles only with `--threadsafe` on the command line, so ordinary CPython source is a hard compile refusal — the wrong side of the upward-compatibility rule. The shim CANNOT declare it: the lock-implementation defines (PXX_TS_HARDLOCK on x86-64, PXX_TS_SOFTLOCK elsewhere) are applied before lexing and the lexer refuses `{$threadsafe on}` saying exactly that. It has to be decided at OPTION time, from a pre-scan of the source, MEASURED 2026-09-20 and the cost question is ANSWERED (chart +0.4%, ARC micro +26%, image +0.9%), so what is left is not a number but a stated intent, escalated as decide-should-a-python-program-that-imports-threading-compile-as-written; the hard part remains that the import can be in a module the main file only reaches transitively — lekkerzeilen/__main__.py has no threading reference at all and needs the mode because it imports app."
---

# `import threading` should imply `--threadsafe`

## The wall

```
$ pascal26 prog.py out
pascal26:16: error: import threading requires --threadsafe: a Python thread
allocates on its first statement and the default heap, ARC and console-I/O
runtime are not thread-safe. Rebuild with --threadsafe.
```

That diagnostic landed with `176b91802` and it is an improvement on what it
replaced (a refusal pointing at `lib/rtl/palthread.pas`, three units below the
line that caused it). **It is still a refusal of source CPython runs.**

## Why the shim cannot fix this itself — measured, not assumed

The obvious design is `{$threadsafe on}` at the top of
`lib/rtl/mimic_threading.pas`, before its own `uses palthread`. Tried, 2026-09-10:

```
pascal26:4: error: {$threadsafe on} must be the --threadsafe flag: the
lock-implementation defines (PXX_TS_HARDLOCK on x86-64, PXX_TS_SOFTLOCK
elsewhere) are applied before lexing, so the directive alone builds an RTL that
disagrees with the codegen
```

The lexer refuses it deliberately and says why. `PasApplyTargetDefines`
(`compiler/paslexer.inc:1052`) runs from `compiler.pas:2003`, before any source
is read, and the defines it sets decide which lock implementation the RTL
compiles. So the decision must be made at OPTION time.

## The hard part, and it is not the flag

A pre-scan of the main file's text covers a program whose own source says
`import threading`. It does **not** cover the case this corpus actually has:

    lekkerzeilen/__main__.py   contains ZERO threading references
                               imports app, which imports threading

So the scan has to follow local imports transitively, and that means a second
implementation of import resolution living in `compiler.pas` before the real
one runs — the classic "second copy that stays wrong". Three options, none
free:

1. **Transitive textual pre-scan** following `import X` / `from X import` to
   sibling `.py` files from the main file's directory. Correct for this corpus.
   Duplicates resolution logic; a package layout the scan does not understand
   silently under-approximates and the program fails exactly as it does today.
2. **Whole-directory scan** — any `.py` under the main file's tree mentioning
   threading turns the mode on. Cannot under-approximate; over-approximates,
   so an unrelated sibling file makes an unrelated program pay for heap and I/O
   locks, and compilation starts depending on files the program never imports.
   Spooky, and hard to explain in a bug report.
3. **`--threadsafe` on by default for the NilPy frontend.** No scan at all, no
   spooky action, always correct. Costs every NilPy program the locked heap,
   ARC and statement-atomic I/O. **Nobody has measured that cost**, and that
   measurement is the thing that would settle this ticket — CPython holds a GIL
   and locks everything, so the comparison may well be favourable.

## What would settle it

**Measure option 3's cost first**, because if it is small the other two are
unnecessary complexity: build the NilPy tier's programs both ways and compare.
A single number would decide a three-way design fork, which is the shape
CLAUDE.md asks for before escalating anything.

Do NOT reach for option 1 because it is the "proper" one. It is the only one of
the three that can be silently wrong.

## Not blocking

`threading` works today with the flag; three tests are green with it. This is
ergonomics and upward-compatibility, not capability — which is why it is 55 and
not higher.

# MEASURED 2026-09-20 (frankb) — the cost question the ticket asked for

Compiler `6b3f65304a6e`, tree at `974db9eb9`, host x86-64. Every runtime row is
min-of-5 inside the program, best of three runs, the two binaries built from
the SAME source by the same compiler and run interleaved.

## What option 3 (`--threadsafe` on by default for NilPy) costs

| workload | off | on | delta |
| --- | --- | --- | --- |
| lekkerzeilen chart (chartbench.py, a real app phase) | 3.384 s | 3.396 s | +0.4% |
| list/alloc churn, 200k iterations | 0.285 s | 0.291 s | +2% |
| string + ARC churn, 200k iterations | 0.043 s | 0.054 s | **+26%** |
| console I/O, 100k lines | 0.511 s | 0.511 s | 0% |
| `print("hello")` image | 1,458,348 B | 1,470,908 B | +12,560 B (+0.9%) |
| `print("hello")` startup | 0.00 s | 0.00 s | below the clock |

CPython on the same two micros: 0.031 s (string/ARC) and 0.040 s (alloc), so
the locked build is 1.7x CPython on the row where locking costs most and the
unlocked build is 1.4x. **The cost is real but small, and it concentrates in
ARC traffic, not in allocation and not in I/O.**

## Two facts that were assumptions until now

**The mode genuinely cannot be switched on at the import.** The comment at
`pasparser_proc.inc` said so; probed rather than believed, by printing the
compiled-unit state at that exact line: `builtinheap` is already compiled and
thirteen units are done. So the decision really is stuck at option time.

**Option 4 (the owner's own "void all and restart", waived 2026-08-10) is not
a doubled compile.** The wasted prefix is only the part before detection:
lekkerzeilen `__main__.py` compiles in ~122 s and the threading import is
refused at **18.5 s**, three runs, 18.60/18.49/18.50. So a restart costs about
**+15%** on the program that motivates this ticket, and ~0 on a small one
(`thr.py` compiles in 2.9 s and detects immediately).

**But it cannot be implemented as a re-exec**: the tree states in three places
that the self-hosted compiler has no `execve`, deliberately. A restart would
mean resetting compiler global state in process, which is a much larger and
riskier change than the "odd hack" framing suggests.

## What changed about the shape of the fork

Option 1's failure mode is better than this ticket credits it. When the
textual scan UNDER-approximates, the user gets **today's refusal**, unchanged —
so option 1 is monotone: never worse than the status quo, sometimes better.
Its real cost is the one frankh-c0 named from inside that code: it is a fourth
reader of the source, with none of the alias or package state the real
resolver has, and it OVER-approximates on a guarded import (`try: import
threading / except ImportError:`), where it would turn locks on for a program
that never threads.

## Why this is now a decide and not an engineering pick

Because option 3 is not refused by its cost — it is refused by a stated intent,
and the intent was stated before anyone had the cost. The owner's rationale
under the opt-in design (recorded in
[[idea-a-auto-enable-threadsafe-by-restarting-the-compile]], 2026-08-10) is
that pxx answers CONCURRENCY with coroutines and async, and that "paying a
locked heap for concurrency you could have had cooperatively is a bad trade".
That is a language stance, not a benchmark, and +0.4% on a real app does not
overturn it. Filed as `decide-should-a-python-program-that-imports-threading-
compile-as-written`.
