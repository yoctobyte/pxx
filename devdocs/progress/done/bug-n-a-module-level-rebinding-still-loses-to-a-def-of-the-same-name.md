---
track: N
prio: 62
type: bug
blocked-by: []
summary: "The MODULE-level arm of the local-binding-beats-a-def fix: `f = o.f` written after `def f` still calls the def. The local/parameter arm is fixed and gated; this one needs module-level bindings to carry a token position, which is a mechanism rather than a patch, so it was split out rather than guessed at."
status: done
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

---

## Resolution 2026-08-27 — the assignment side gets a position

Built the mechanism the ticket asked for rather than a narrower rule, and the
ticket's own reasoning about which one it had to be held up.

**`ProcPyRebindTok`** (defs.inc, beside `ProcPyDefTok`) records, per module-level
def, the token index of the first module-level assignment that rebinds its name —
`-1` for none, `-2` for not-yet-computed. **`PyDefRebindTok`** (symtab.inc) fills
it lazily on first ask; **`PyDefRebound`** answers the question the call sites
need:

```pascal
Result := (CurProc >= 0) or (rb < TokPos);
```

Inside a def BODY the position does not matter — the body runs after the whole
module has executed, so a rebinding anywhere at module level is what the name
means by then. In the module body it is an ordinary lexical comparison, the same
one `ProcPyDefTok` has always supported from the other side.

Only **depth 0** assignments count, which is the ticket's own constraint honoured
literally: `f = something` under a branch that never runs must leave the def in
place, because that program is legal CPython and NilPy is upward compatible.
Row 5 of the test pins it.

`FindProc` was not re-ranked — the warning above `MatchElig` stands.

### Two measured wrong turns, both worth recording

**1. `PyDefBoundHere` is the wrong funnel, even though it is the right question.**
The obvious move is to extend it: it is documented as the one place "is this def
bound at the cursor" is asked, from three call sites. Done, and measured — the
funnel answered **correctly** (`PXXDBG` probe: `deftok=1 rebind=11 TokPos=20`,
so `Result := False`), and the program still called the def.

The reason is a few thousand lines below the unbind: the `pyLateDefPi` path
restores the proc when *"nothing claimed the name"*, and a module GLOBAL never
claims it — the variable arm sits after the restore. That is why the fix has to
be the same shape as the local arm, at the same site, unbinding **permanently**,
and why `skGlobal` is a real condition rather than a formality: it is what
guarantees there is something for the ordinary variable path to pick up.

**2. The ticket points at the wrong file, and the pointer looks right.** It names
"the bare-ident arm of `ParseFactorCore` — since the 2026-08-20 parser split this
is `compiler/pasparser_expr.inc`". There is such an arm there, carrying the local
fix's comment verbatim, guarded by `NilPyUserCode` — and it is **not the one that
runs**. NilPy has its own copy at `pyparser.inc:45040`, which is the live one;
the `pasparser_expr.inc` copy is Pascal's parser and never fires for these
programs. A probe printing nothing at all is what showed it, after an edit that
built clean and changed no behaviour.

This is `the-substrate-is-ast-and-ir-not-the-parser` working as intended —
duplicate the parser per language — but it means a slug grep returns two hits and
only one of them matters. Grep for the slug, then check which copy the frontend
actually reaches.

## Gate

| row | pxx | CPython |
| --- | --- | --- |
| `f = D().f` after `def f` | `METH` | `METH` |
| `g = lambda: 2` — the smallest form, no class | `2` | `2` |
| a call ABOVE the rebinding | `1` | `1` |
| ...and below it | `2` | `2` |
| def-vs-def ordering (already worked) | `2` | `2` |
| a rebinding under `if False:` — must NOT displace the def | `1` | `1` |
| the rebinding seen from inside a def BODY | `2` | `2` |

22 named name-resolution canaries green (`local_binding_beats_a_def`,
`def_redefined_rebinds_only_after`, `redefine_def`,
`def_shadows_builtin_positionally`, `min_max_variadic`,
`user_def_shadows_a_builtin`, `def_local_shadows_module_global`,
`field_holding_a_def`, `function_identity`, `key_callable_reads_every_default`,
…). `test_nilpy_cross_module_defaults` needs `-Futest/nilpy_units` and was
verified byte-identical to the v387 pinned binary with it. Self-host fixedpoint
verified, `converged after 1 round(s)`.

**Test:** `test/test_nilpy_module_rebinding_beats_a_def.npy` (+`.expected`,
registered) — the seven rows above.

## Split out, NOT fixed here

The ticket's third measured row — a `def` inside a TAKEN branch not rebinding at
all — is the **def** side of the same comparison and a different mechanism:
`PyRegisterDefShells` walks module-level defs at depth 0 only, so a def inside an
`if` never gets a `ProcPyDefTok` to compare with. Re-measured at `e8b72f8afeb6`
and unchanged by this fix. Filed as
[[bug-n-a-def-inside-a-taken-branch-does-not-rebind-the-name]] (p45) rather than
left in a resolved ticket, with the note that the honest answer may be that
conditional bindings stay untracked in BOTH directions — which is a Track U
question, not one to settle in passing.

## Log
- 2026-08-27 — resolved, commit d5a501b4e.
