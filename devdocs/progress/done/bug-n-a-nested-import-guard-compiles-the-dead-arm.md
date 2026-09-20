---
slug: bug-n-a-nested-import-guard-compiles-the-dead-arm
title: a nested import guard compiles the arm the program excluded
summary: >
  FIXED (this ticket's commit). THE EXCLUDED ARM DID NOT MERELY COMPILE, IT
  RAN -- module-level code executing from a branch the source excluded, in a
  program where CPython never imports that module at all. Compiling an excluded
  arm is a correctness bug; RUNNING one is a different category, because the
  program can do something irreversible before anyone reads a wrong value.
  Measured with a `print` in a dead arm against the pinned compiler, and it
  needs ONLY THE NESTING: no shared name, no `else:`. THE OBSERVABLE WAS
  OTHERWISE SILENT AND THE REPORTED REFUSAL IS THE RARE HALF. ON TOP
  of it, a WRONG VALUE whenever both arms bind the same name and the live arm
  is lexically AFTER the dead one (an `else:` clause, or a deeper arm): the
  unit-alias table is first-wins, so the dead arm answers every member read
  through the live arm's name, exit 0, no diagnostic. In the ordinary no-`else`
  idiom the live arm is lexically first and wins by position, so the value is
  right and only the side effect leaks. The reported case errors only because
  its dead arm imports `ctypes`, which pxx cannot compile. MECHANISM:
  PyPreScanImports tracked ONE try and keyed arm-deadness on `depth <= tryAt`,
  where `tryAt` is that try's DEPTH -- a nested guard left it at the OUTER
  try's depth, so the test was false at every clause boundary of the inner one
  and the logic never ran. Now a stack, and the dedent handler is a LOOP
  because one DEDENT can close several tries. `try: import X / except
  ImportError:` is the only conditional compilation Python has, so this was a
  correctness bug in a language feature at every nesting depth.
track: N
type: bug
prio: 70
owner: frankb-8e
status: done
---

# A nested import guard compiles the arm the program excluded

## Why this is a correctness bug and not an unsupported shape

The owner's framing, relayed 2026-09-20, and it is the reason this is not an
edge case:

> *"plus, we only do so due to lack of `#define` and python's design. so, this
> is by design."*

C has a preprocessor. Python decides at import time and expects `ImportError`
to be caught, so `try: import X / except ImportError:` **is** Python's
`#ifdef` -- the only conditional-compilation mechanism the language has. NilPy
resolving it at COMPILE time honours that intent rather than bending it.

A NESTED guard is therefore **nested conditional compilation**, and resolving
an arm the program excluded is **compiling code the source said not to
compile**. That framing decides the fix's shape: the feature was wrong at every
nesting depth, so the fixture asserts three levels rather than the two the
report happened to contain.

## Where it was filed, and the gap that matters more than the bug

Reported as **lekkerzeilen blocker 07**, in the *lekkerzeilen* repo
(`devdocs/pxx-blockers/07-nested-import-guard-compiles-the-dead-arm/`, commit
`5a7fc43`) -- a **pxx compiler bug with no pxx ticket**. Invisible to
`tools/progress.sh ready`, to the ranker, and to Track T, and a citation into
another repo's tree is not something a pxx seat can resolve. This ticket is the
pxx-side home; the fixture below is the reduction's second home, restated
against modules a pxx seat can run.

## Reproduce

Two 10-line packages differing only in nesting. Flat compiles and prints 7;
nested is refused:

```python
try:
    import __pxx__               # absent -> handler
except ImportError:
    try:
        import ctypes           # absent under pxx -> handler
    except ImportError:
        from . import _native as _backend
    else:
        from . import _ct as _backend    # DEAD, and compiled anyway
```

    pascal26:3: error: no member c_uint came of the qualifier ctypes
      in: .../repro_nested/_ct.py

Reproduced at HEAD compiler `dc03cd5e78e3`, not only at the reported
`ec905950c45a0bc1`.

## The boundary, measured before anything was read

Twelve variants, one axis at a time. `else` present unless noted; every row
prints 7 when correct.

| where the guard sits | before |
| --- | --- |
| top level | ok |
| inside `if True:` | ok |
| inside a `def` | ok |
| inside a `for` | ok |
| inside a `try` BODY | **REFUSED** |
| inside an `except ValueError:` handler | **REFUSED** |
| inside an `except ImportError:` handler (the report) | **REFUSED** |
| inside a handler, guard has no `else` | ok |

**The trigger is an enclosing `try`, not an enclosing block and not the
fallback handler specifically** -- `except ValueError` breaks it too. The
no-`else` row is NOT a control and nearly filed the diagnosis wrong: removing
the `else` removes the dead arm entirely, so there is nothing left to compile
wrongly. The row that actually discriminates puts the dead arm in the HANDLER
and lets the try body resolve (`import math`), which fails inside an outer try
and passes at top level -- same guard, same arms, only the nesting differs.

### THE TWO TRIES NEED NOT BE ADJACENT

The enclosing `try` can be any distance away, through any intervening
construct, because the pre-scan compares INDENT depth against the tracked try's
depth and an ordinary block pushes the guard deeper just as a `try` does.
Measured:

```python
try:
    x = 1
    if x == 1:              # an ordinary block BETWEEN the two tries
        try:
            import math
        except ImportError:
            from . import dead as impl
        else:
            from . import live as impl
except ValueError:
    pass
```

    CPython   impl live
    pinned    SIDE EFFECT: dead arm ran / impl dead
    HEAD      impl live

Both halves fire. **So an audit for affected code must ask whether any `try`
lexically CONTAINS another `try` that guards an import — at any distance.** A
search for `try:` directly inside `try:` answers zero on the block above.

Noted because the first audit of a downstream application asked about
"try-depth 2+", and a depth number is a proxy for a lexical-containment
question rather than the question itself.

### And that table answers only the REFUSAL question, which is the rare half

Every "ok" above means *compiled and printed 7*. It does NOT mean the program
behaved. Measured afterwards, against `stable_linux_amd64/default/pinned`, with
a `print` at module level in the dead arm:

| | CPython | pinned (pre-fix) | HEAD |
| --- | --- | --- | --- |
| live arm is an `else:` | `impl live` | **side effect RAN**, `impl dead` | `impl live` |
| no `else:`, live arm first | `impl live-try` | **side effect RAN**, `impl live-try` | `impl live-try` |

**The excluded module's top-level code EXECUTED**, in a program where CPython
never imports it at all. That half needs only the nesting — no name collision,
no `else:`.

The WRONG VALUE needs more: both arms binding the same name AND the live arm
lexically AFTER the dead one. The unit-alias table is first-wins, so in the
ordinary no-`else` idiom the live arm is lexically first and wins by position —
the value is right and only the side effect leaks, which is why the second row
looks clean and is not.

So the row marked "ok, guard has no `else`" in the boundary table is **ok for
the question that table asked** and was never a clean bill of health. Stated
separately because a reader scanning the table would otherwise carry away that
the no-`else` idiom was unaffected.

## Mechanism

`PyPreScanImports` walks every import token ahead of the parse and resolves it.
It tracked one try in scalars, and **`tryAt` holds a DEPTH, not a token index**.

**The two lines below are the PRE-FIX source and are no longer in the tree** —
do not grep for them expecting a hit; the current shape is the stack described
under Fix:

```pascal
else if (Tokens[i].Kind = tkTry) and (tryAt < 0) then   { nested try IGNORED }
  tryAt := depth;
...
if (tryAt >= 0) and (depth <= tryAt) then                { clause logic }
```

An inner try never became current, so at its clause boundaries `depth` was
greater than the OUTER try's `tryAt` and the arm-deadness test was skipped
entirely. Measured with the tag added by this commit:

    vL (top level, works)     DEDENT to depth 0 tryAt=0 -> clause logic 1
    vK (inside a try, broken) DEDENT to depth 1 tryAt=0 -> clause logic 0

and the inner `try` produced no `TRACKED` line at all.

**Why the flat case was always right**: at top level the single tracked try IS
the guard, so the depth key is correct there. The suite covered the one
arrangement in which the broken key gives the right answer.

**Why the parser layer was innocent, and how that was established rather than
assumed**: a tag on `PyIsFallbackImportTry` printed NOTHING for the broken
shape -- not even for the outer try. A predicate that is never called cannot be
the layer at fault, and the silence named the pre-scan in one run.

## Fix

A stack, one entry per open try, pushed on every `tkTry` and popped when the
try statement ends. Two things that are not obvious:

- **The dedent handler had to become a LOOP.** One DEDENT can close an inner
  guard's last block AND the handler of the try it sits in, so the enclosing
  level's clause must be examined on the same token. An `if` there handles the
  innermost and silently drops every level above it -- which would have made
  this a fix for exactly one nesting depth, the depth the reduction happened to
  have.
- **Overflow degrades, it does not mis-pair.** Past 32 open tries the new try
  is not pushed and is never popped either, because a pop is triggered by
  comparing `depth` against the top's own `tryAt` and not by counting tries.
  The enclosing level simply keeps deciding, which is what every depth did
  before today.

A miss now marks the INNERMOST open try rather than the outermost, which is the
correct reading: an inner guard catches its own `ImportError`.

## Fixture

`test/test_nilpy_a_nested_import_guard_does_not_compile_the_dead_arm.npy` with
package `test/nilpy_nestguard/`, wired into `test-nilpy` beside the flat
sibling it complements.

**THREE deep, not two** -- a fix restoring only the second level passes a
two-deep fixture.

**No row guards on `ctypes`**, for the reason `nilpy_tryelse`'s header already
records: CPython resolves it and pxx does not, so oracle and subject would run
DIFFERENT arms and the differential could never fail. Two modules absent under
both runtimes, plus `math`, present under both. The reduction uses `ctypes`
correctly -- it is about a real backend -- and that is exactly what stops it
being a differential test.

**POSITIVE CONTROL, and it is SILENT**, which is why the fixture asserts a
value and not a compile. Against `stable_linux_amd64/default/pinned` (v412,
predating the fix), exit 0 and no diagnostic:

| | WHICH | unit alias | symbol | floor |
| --- | --- | --- | --- | --- |
| correct | `deep-else` | `deep-hit` | `sym-deep-hit` | 2 |
| pinned | `deep-else` | **`deep-miss`** | **`sym-mid-else`** | 2 |

`WHICH` is right -- the parser selected the correct arm -- and both member
reads are wrong, **by different dead arms**: the unit alias answers `deep_miss`
(first-wins, and the live arm is lexically last on purpose), the symbol answers
`mid_else` through flat unit scope. The reported reduction fails loudly only
because its dead arm imports `ctypes`; where a dead arm is ordinary Python the
whole thing is a plausible wrong value far from the cause.

### What the fixture does NOT assert, and why it was not added

**The SIDE-EFFECT half has no row.** The fixture catches the wrong-value half
only: its arm modules declare constants, so a regression that resolved a dead
arm again would be caught by the alias answering `deep-miss`, but a regression
that ran a dead arm's top-level code WITHOUT changing any binding would pass.
Given the no-`else` measurement above — value correct, side effect leaked —
that combination is real and not hypothetical.

Not added because the measurement arrived while the tier was already running on
this fixture, and editing a test file mid-run means the suite grades a version
nobody ran locally first. The row is one `print` in a dead arm plus the
matching oracle line; it belongs in the next sitting, with its own tier.
**Recorded here rather than remembered**, because a fixture that covers one of
two halves reads as covering the defect.

## What this unblocks

**lekkerzeilen's backend block, on both compilers that exist today, with no
dependency on the marker-module name.** Trace, with the nested guard working:

| compiler | path | result |
| --- | --- | --- |
| today's pxx | marker absent -> `ctypes` absent -> `_native` | correct |
| CPython | marker absent -> `ctypes` present -> `_ct` | correct |
| a future pxx shipping the marker | first arm | correct |

So the marker module is a SIMPLIFICATION and this was the unblocker -- the
reverse of how the dependency was described while it was open. Measured here
for the two compilers that exist; the third row is untestable until a marker
ships and is labelled so rather than claimed.

## Instruments left behind

Two `PXXDBG` tags, because this area is a known two-layer trap -- the compiler's
own comment says *"THE PARSER NEEDS THE SAME SKIP AND HAS ITS OWN ... fixing
either alone changes nothing"*:

- **`n.impguard`** -- `PyIsFallbackImportTry`'s verdict and, on a refusal, the
  clause that refused. Every answer it gives is a SILENT routing decision:
  False sends the guard to `PyParseTry`, which parses both arms, and the error
  then surfaces inside a module on the branch the program does not take, at
  that module's own line, with nothing naming the try that caused it.
- **`n.impscan`** -- the pre-scan's try stack and, at each clause boundary,
  whether the arm logic ran. This is the one that found the bug.

`n.impscan`'s `open=` count was printed BEFORE the push for an hour and read
one too few for every nested try -- an instrument understating exactly the
quantity the fix is about. Corrected before landing.

## Log
- 2026-09-20 — filed and fixed in one sitting; reported as lekkerzeilen blocker 07 with no pxx-side ticket, which is the coordination gap this file closes.
