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
and the decision site (`compiler/parser.inc`, the bare-ident arm of
`ParseFactorCore`) cannot see it. A `def` has `ProcPyDefTok` to compare against
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
