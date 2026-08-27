
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
