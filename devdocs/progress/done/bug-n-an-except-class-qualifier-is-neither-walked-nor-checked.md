---
slug: bug-n-an-except-class-qualifier-is-neither-walked-nor-checked
track: N
type: bug
prio: 75
status: done
owner: frankZ
created: 2026-09-11
found-by: frankB
tags: [nilpy, exceptions, lekkerzeilen, silent-wrong-value]
blocked-by: []
summary: "FIXED 2026-09-11 (compiler `fe40bf55e141`). An `except` arm's qualifier was consumed by an `if`, not a loop, in TWO copies -- so `except (urllib.error.URLError, OSError, ValueError):` took the MIDDLE segment as the class and died as `unknown exception class error`. That is gauges.py:422 and it is the standard spelling, urllib publishing its exceptions from a submodule. The axis is dot DEPTH, not the tuple: one dot worked bare/in a tuple/first/last, two dots failed in all four plus `as e`. AND THE LARGER HALF, found by frankB: the qualifier was never CHECKED, only discarded, so `except zzz_nothing.Error:` COMPILED and CAUGHT a `sqlite3.Error` -- a handler binding to a class the program never named, case-insensitively, fleet-wide the moment mimic_sqlite3 landed a class called `Error`. Both halves fixed in one extracted routine: walk the qualifier whole, and require some dotted prefix of it to name a unit (any prefix, because `import urllib.error` gives the joined unit `urllib_error` and a root-only check would refuse the corpus's own spelling). CPython is the oracle on eight shapes. CORPUS: unblocks gauges.py:422 and, through the cascade, __main__.py."
---

# The two halves, measured 2026-09-11

**Half one, the symptom.** `PyParseTry` ate a qualifier with

```pascal
if (CurTok.Kind = tkDot) and (Tokens[TokPos].Kind = tkIdent) then
```

`if`, so exactly one dot. `urllib.error.URLError` became className `error`.

**The axis is not the one the symptom suggests.** It arrived as "a dotted class
in an except TUPLE". The tuple is irrelevant:

| shape | before |
| --- | --- |
| `except ValueError:` / `except (ValueError, OSError):` | ok |
| `except json.JSONDecodeError:` / in a tuple, first or last | ok |
| `except urllib.error.URLError:` | **fails** |
| in a tuple, first / last / with `as e` | **fails** |

**Half two, frankB's, and it is the larger one.** The qualifier was not
checked — it was consumed and thrown away, and the last segment resolved flat
and case-insensitively. So:

```python
import sqlite3
try:
    raise sqlite3.Error("x")
except zzz_nothing.Error:        # zzz_nothing does not exist
    print("caught")              # <- this ran
```

**`except <anything>.Error:` caught sqlite3's `Error`.** CPython raises
`NameError` at that clause. This is not NilPy accepting more than CPython — which
is a feature by Track N's rule — it is **a handler binding to a class the source
did not name**, in the one construct where a wrong answer is least likely to be
noticed. It became fleet-wide the moment `mimic_sqlite3` put a class called
`Error` in the flat namespace, which frankB flagged against their own commit.

# One diagnostic, two messages, and neither is about the tree

The same source produced `unknown exception class error` for me and
`expected ')' before '.'` for frankB. **The discriminator is `import sqlite3`
and nothing else.** With `mimic_sqlite3` in scope the middle segment `error`
RESOLVES (flat, case-insensitive), so the parser accepts `urllib.error` as a
complete qualified class and then meets `.URLError` — a syntax error about `)`.
Without it, nothing named `error` exists and it stops one token earlier naming
what it could not resolve.

**Two messages for one construct, and which you get depends on whether some unit
in scope happens to declare a class spelled like the qualifier's last-but-one
segment.** Neither of us could have written one ticket from the other's message.
The same-line-number rule's sibling: here the MESSAGE, not the line, is the
manufactured equivalence class — and it is manufactured by what else is linked.

# The fix

One routine, `PyConsumeExceptClassName`, called from the tuple arm and the
single arm. It walks the qualifier whole and then requires that **some dotted
prefix of it names a unit**.

Any prefix, not the root: `import urllib.error` yields the joined unit
`urllib_error` (then chased to its shim), so `FindUnitOrAlias('urllib')` answers
nothing and a root-only check would refuse the corpus's own spelling. Measured
before it was written, not after.

**EXTRACTED, NOT FIXED TWICE.** The tuple arm's own comment records that it got
qualifier support by copying the single-class arm — *"The single form below has
taken this since tk.TclError; the tuple form did not"* — so the one-dot limit was
duplicated along with the feature. That is `normalise-dont-special-case` in the
variant that rule does not spell out: the second path was not STALE, it was a
COPY, so it was wrong in exactly the same way and "fix one, grep for the sibling"
would have found a sibling that already looked correct.

# Controls

- **Positive, measured:** the PINNED compiler fails the new test at **line 42**,
  `unknown exception class error` — the exact line and message of the bug.
- **The arms are asserted to CATCH, not merely to compile.** A compile cannot see
  which class an arm resolved to. The test raises and prints which arm caught;
  the `ValueError` row is the control against an over-broad resolution swallowing
  everything, and it is inside the same run so an arm that caught everything
  would fail it.
- **All eight shapes are rows**, one-dot included, so a later regression cannot
  fix depth by breaking depth-1.
- **Four garbage-qualifier probes** now refused with the qualifier named.
- **The rest of the qualified-except population re-run**, one by one, all of it:
  `the_sqlite3_module` (five arms, one a tuple with `as`) the Makefile's own way
  with `PXX_SQLTEST_DIR`, `the_queue_module` and `a_queue_across_two_threads`
  (`queue.Empty`/`Full`), `pyexception_bare_vs_qualified` (`su.Exception`, a
  quoted-import alias). Plus the fifteen import-family neighbours from
  `bug-n-a-dead-guarded-import-arm-still-binds-its-unit-alias`.

# Two mistakes of mine worth keeping

**The rewrite dropped a `Next;`**, so the loop never ran and every qualified
arm errored on the ROOT. Caught immediately — by the test, not by review.

**And the verification printed `IDENTICAL to CPython` against a STALE BINARY.**
The compile had failed; the diff ran against the previous run's artefact, which
was still on disk and still executable. `A && B` was written as two statements.
That is the playbook's *"assert the PRECONDITION, not just the comparison"* in
its purest form, committed by someone who had quoted the rule earlier the same
evening — the harness now asserts the compile succeeded AND that the binary
exists before it diffs, and deletes the artefact first so a stale one cannot
answer.
