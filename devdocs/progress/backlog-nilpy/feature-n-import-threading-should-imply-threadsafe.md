---
slug: feature-n-import-threading-should-imply-threadsafe
track: N
type: feature
prio: 55
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, threading, options, upward-compat]
blocked-by: []
summary: "`import threading` compiles only with `--threadsafe` on the command line, so ordinary CPython source is a hard compile refusal — the wrong side of the upward-compatibility rule. The shim CANNOT declare it: the lock-implementation defines (PXX_TS_HARDLOCK on x86-64, PXX_TS_SOFTLOCK elsewhere) are applied before lexing and the lexer refuses `{$threadsafe on}` saying exactly that. It has to be decided at OPTION time, from a pre-scan of the source, and the hard part is that the import can be in a module the main file only reaches transitively — lekkerzeilen/__main__.py has no threading reference at all and needs the mode because it imports app."
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
