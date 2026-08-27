---
track: N
prio: 62
type: bug
blocked-by: []
summary: "The MODULE-level arm of the local-binding-beats-a-def fix: `f = o.f` written after `def f` still calls the def. The local/parameter arm is fixed and gated; this one needs module-level bindings to carry a token position, which is a mechanism rather than a patch, so it was split out rather than guessed at."
---

# A module-level rebinding still loses to a `def` of the same name

```python
def f(x):
    return "MOD"
class D:
    def f(self, x):
        return "METH"
f = D().f
print(f("q"))        # pxx: MOD        CPython: METH
```

The LOCAL arm of this — the same rebinding inside a function body — is fixed
and wired
([[bug-nilpy-a-callable-in-a-variable-loses-to-a-def-of-the-same-name]],
`test/test_nilpy_local_binding_beats_a_def.npy`). This is the remaining row of
that ticket's table, split out rather than left as a footnote on a resolved
ticket.

## Why it was split rather than fixed with the other arm

The local arm needs no ordering: Python's scoping makes a local binding win for
the WHOLE function body unconditionally, so `Syms[idx].Kind in [skLocal,
skParam]` is the entire test.

At module level that is not true — the answer is "whichever statement ran last",
and the decision site (the bare-ident arm of `ParseFactorCore` — since the
2026-08-20 parser split this is `compiler/pasparser_expr.inc`, NOT the
`compiler/parser.inc` this ticket was filed against, which no longer exists)
cannot see it. A `def` has `ProcPyDefTok` to compare against
`TokPos`, which is exactly how the late-`def` rule a few lines below works; an
ordinary module-level assignment has no equivalent record.

So the fix is to give module-level bindings a token position and extend the same
comparison to them. That is a mechanism, and
`devdocs/dev/root-cause-over-microfix.md` says to bank it rather than
microfix — a narrower rule that ignores order would break the legal forward
case (`f = something` guarded by a branch that never runs) which NilPy must
accept, being upward compatible with CPython.

**Do NOT fix by re-ranking `FindProc`** — see the warning above `MatchElig` in
`symtab.inc`. That was tried and broke the compiler's own self-compile and the
NilPy stdlib.

## Priority

Lower than the local arm was (p70 → p45): the third-party corpus wall that
justified the urgency was the local shape, and it is cleared. This arm has no
known corpus consumer yet.

## Two more rows, measured 2026-08-27

Found while fixing [[bug-nilpy-redefining-a-def-rebinds-calls-that-came-before-it]]
(the def-vs-def ordering arm). Both are PRE-EXISTING — identical on the v384
pinned binary and on the fixedpoint that carries that fix — so they were left
out of it deliberately rather than missed.

**A `lambda` rebinding is the same row as the `o.f` one above:**

```python
def f():
    return 1
f = lambda: 2
print(f())           # pxx: 1        CPython: 2
```

Same mechanism, same fix: a module-level assignment carries no token position,
so it cannot beat the def's `ProcPyDefTok`. Worth keeping in the repro set
because it needs no class and no bound method — it is the smallest form.

**A `def` inside a TAKEN branch does not rebind at all — different mechanism:**

```python
def g():
    return 1
if True:
    def g():
        return 2
print(g())           # pxx: 1        CPython: 2
```

This one is NOT the missing-token-position problem: a `def` does have
`ProcPyDefTok`. It is that `PyRegisterDefShells` walks **depth 0 only**, so a
def one indent in never registers a module-level shell and never becomes a
candidate. The complement of it is already right for the wrong reason — with
`if False:` pxx prints `1`, matching CPython, because the def is invisible
rather than because the branch was evaluated.

Fixing this properly means deciding what a conditionally-bound module-level name
resolves to when the compiler cannot know which branch runs, which is a Track U
question, not a patch. The honest intermediate is that the LAST textual def
wins from its position on, matching the unconditional rule — wrong for
`if False:` (where it is currently accidentally right) and right for `if True:`.
That trade is the decision, and it should be made before either behaviour is
coded.
