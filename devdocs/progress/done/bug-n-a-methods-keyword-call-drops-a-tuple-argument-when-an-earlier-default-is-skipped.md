---
track: N
prio: 55
type: bug
blocked-by: []
summary: "A NilPy keyword call to a METHOD that leaves an earlier defaulted parameter unbound rejects an object-valued (tuple/list) argument: `no overload of X matches these arguments`. The identical signature and call binds correctly through the INSTANTIATION path and through a unit-level procedure. Scalars are unaffected. Blocks tkinter's `grid(padx=(8, 6))`."
status: done
owner: frankwasm
---

# A method's keyword call drops a tuple argument when an earlier default is skipped

- **Type:** bug — **Track N** (NilPy argument binding). Filed 2026-08-29 by
  frank-b (Track B) out of
  [[feature-lib-tkinter-grid-pad-accepts-a-two-tuple]], which is not a Track B
  defect: the tkinter facade is already complete and correct (below).
- **Measured at:** pin v393 `1d69760deabe`.

## The minimal repro — one class, two call paths

```pascal
unit vunit6;
interface
type
  TC = class
  public
    constructor Create(a: Integer = -1; const s: AnsiString = ''; const v: Variant = 0);
    procedure meth(a: Integer = -1; const s: AnsiString = ''; const v: Variant = 0);
  end;
```

```python
import 'vunit6.pas' as v6
c = v6.TC(a=0, v=(8, 6))     # OK   -> ctor tag=7
c.meth(a=0, v=(8, 6))        # FAILS -> no overload of meth matches these arguments
```

Same class, same parameter list, same call, same skipped parameter (`s`). Only
the *path* differs. That is the whole finding: **two argument-binding paths
serve one concept and only one of them fills defaults correctly for an
object-valued Variant.** The fix is presumably to make the method path do what
the instantiation path already does, rather than to patch the matcher.

## The boundary, measured

Every row is a keyword call with a `(8, 6)` argument unless stated.

| shape | result |
| --- | --- |
| unit-level procedure, gap before the Variant | **OK** |
| class instantiation `TC(a=0, v=(8,6))`, gap before | **OK** |
| **method** `c.meth(a=0, v=(8,6))`, gap before | **FAILS** |
| method, *no* gap — every parameter supplied | OK |
| method, gap, argument is a **scalar** `v=8` | OK |
| method, gap, Variant is the **first** parameter (gap after it) | OK |
| method, gap before a skipped **AnsiString** target (no Variant) | OK |
| explicit constructor call `TC.Make(a=0, v=(8,6))` | **FAILS** |
| positional first arg, `meth(0, v=(8,6))` | FAILS |
| tuple `(8,6)` vs list `[8,6]` | identical — both fail |

So all three conditions are required: a **method call**, a **defaulted
parameter left unbound before** the argument, and an **object-valued** Variant
(`pyvartag` 7). Miss any one and it binds.

Note `TC.Make(...)` — an explicit constructor call — fails while `TC(...)`
succeeds, which says the split is call-path and not constructor-vs-method.

## Where it is not

The diagnostic is raised at `compiler/pasparser_call.inc:2033`, but that is
where the failure is *reported*, not where it is caused: Pascal cannot express
a skipped middle default at all, so the gap can only have been created by
NilPy's keyword binding when it built the argument list. Start at the
NilPy side and at the difference between the two paths, not at the matcher.

## Impact

Blocks [[feature-lib-tkinter-grid-pad-accepts-a-two-tuple]], and through it
`settings.py` in [[feature-demo-songformatter-pxx-target]]. It is wider than
tkinter, though: any NilPy call into a Pascal facade whose methods take
optional Variant options — which is the shape every facade here uses — hits
this the moment an application passes a tuple without also supplying every
preceding option. `pack(padx=(8, 6))` fails for the same reason
`grid(row=0, column=0, padx=(8, 6))` does.

## What is already correct, so nobody re-does it

The tkinter facade needs no change. `padx`/`pady` on both `grid` and `pack` are
already `Variant`, and `TkiOptPad` already renders the pair as Tk's braced
list. Verified by asking **Tk** rather than our own formatter — `grid info` on
the live widgets:

```
pair  : ... -padx {8 6} -pady 2 -sticky e
scalar: ... -padx 8 -pady 2 -sticky e
pady  : ... -padx 1 -pady {3 9} -sticky e
```

reached by supplying every intermediate option to dodge this bug:
`grid(row=0, column=0, sticky="e", columnspan=1, rowspan=1, padx=(8, 6), pady=2)`
compiles and applies asymmetric padding today. That is also the **workaround**
for an application that cannot wait: name every option before the pad.

## Gate

Track N's: `make test-nilpy` green + self-host byte-identical. The repro above
must bind through the method path, and the `TC(...)` / unit-level rows must
stay green (they are the control, not the target).

---

## A same-widget, same-method pair in real code (frankwasm, 2026-08-30)

Found while re-running songformatter against HEAD. `settings.py` calls
`tk.Label(...).grid(...)` twice, nine lines apart, on the **same widget class**
and the **same method** — and one compiles while the other does not:

```python
sect_label = tk.Label(self.content, text=section, anchor="w", font=(...))
sect_label.grid(row=row, column=0, columnspan=2, sticky="we", padx=8, pady=(10, 2))   # line 178 — COMPILES
...
label = tk.Label(self.content, text=key, anchor="e")
label.grid(row=row, column=0, sticky="e", padx=(8, 6), pady=2)                        # line 183 — FAILS
```

`pascal26:183: error: no overload of grid matches these arguments`. Line 178 is
before it and produced no error, so it bound.

The tuple is present in **both**. What differs is only **which keyword carries
it** — `pady` at 178, `padx` at 183 — plus the presence of `columnspan` at 178,
which changes how many earlier defaults are skipped. That is a controlled pair
the synthetic repro cannot express: same receiver type, same method, same
signature, tuple in both, opposite outcomes.

So the defect is **not** "a tuple argument is rejected". It is positional: a
tuple is rejected at some argument slots and accepted at others, as a function
of which earlier defaulted parameters were left unbound — which is what this
ticket's title already says, now with real-code evidence for the *accepted*
half. Any fix should assert both lines, since a fix that makes tuples work
everywhere would pass a test built only from line 183.

**This is the wall songformatter is standing at.** It blocks `settings.py`,
`convertrawtext.py` and `SongFormatter.py`, all three at a `grid(padx=(...))`
call. `key_analysis.py` compiles clean.

## Grant, 2026-08-30 — frank-coordinator to the wasm/N lane: land it in `pasparser_call.inc`

**The defect is not in `pyparser.inc`.** It is `FindUMethOverloadAhead` in
`compiler/pasparser_call.inc:1733` — the speculative type-aware method-overload
probe. `PyKwArgIndex` and `PyBindKwArgs` are correct and **never run**: the probe
refuses the call before binding is reached.

**Mechanism.** The probe steps over a NilPy `name=expr` keyword deliberately, so
the name is not parsed as an expression, and its own comment states the
assumption:

> *"The probe only needs the argument's TYPE; which parameter it binds to is
> settled later by `PyKwArgIndex`."*

True of what the loops below want to know, **false of how they index** — both are
positional, `Procs[pi].Params[base + j]` (lines 1939, 1946). So
`meth(a=0, v=(8,6))` against `meth(a; s: AnsiString; v: Variant)` judges argument
1 against **`s`**, a tuple lands on a string slot, the reference-shaped-argument
guard fires, and a legal call is refused. Predicted before measuring, then
confirmed on every row: tuple→string FAILS, tuple→int FAILS, no-gap OK, scalar
OK — and it explains why the ctor and the unit-level proc pass, since neither
path runs the probe.

**Second exposure, same root, and it is the more serious one.** The *ranking*
loop indexes positionally too, so an overloaded method called with keywords that
skip a default is ranked against the wrong parameters — **silent wrong-overload
selection, not a diagnostic.** Under CLAUDE.md's table that is the
silent-wrong-behaviour escape, and it is why this is one fix rather than a patch.

**Granted: land it, with A's gate.** `pasparser_call.inc` is a Pascal-frontend
file shared with Track A, so the fixedpoint alone is not enough —
`tools/gate.sh quick` is required on top of it. Verified free rather than assumed
free: `tools/fleet_dirt.sh` across 15 discovered checkouts shows **only**
`~/pxx-songfmt` holding the file; frankA is in `pasparser_stmt.inc`, frank-rust
in `pasparser_generic.inc`.

The lane holder correctly refused to push it under Track N and held a built,
verified, uncommitted fix pending placement rather than assuming. That is the
right call and the reason the grant is cheap to make.

**Fix shape:** `OverloadArgParamIdx` records the keyword name as a token index and
resolves it per candidate, used by both loops, **abstaining rather than
rejecting** when the name is not a declared parameter, so `**kwargs` callees are
unaffected. Both halves of the boundary asserted — `settings.py:178` (which
already worked) as well as `:183`.

## Follow-up filed separately: the code is in the wrong file by name

The broken code sits behind `if isNilPy` **inside a file named for the Pascal
parser**. `the-substrate-is-ast-and-ir-not-the-parser.md` is being violated by
filename: a NilPy calling-convention concern living in `pasparser_call.inc` is
exactly why a Track N ticket routed its holder into a file Track N does not own,
and why the collision question had to be asked at all. Worth its own ticket
independently of who lands this fix — the `isNilPy` branching in that file is
dense (lines 613, 634, 1147, 1767, 1851, 1888, 2131), so this is a carve-out
question, not a one-line move.

---

## Resolution, 2026-08-30 (frankwasm), under the grant at `e268f9990`

### It was never the keyword binder

`PyKwArgIndex` and `PyBindKwArgs` are correct and the call never reaches them.
The refusal comes from `FindUMethOverloadAhead`
(`compiler/pasparser_call.inc:1733`), the speculative type-aware method-overload
probe, which runs first.

The probe parses the argument list speculatively to learn argument **types**.
For a NilPy `name=expr` it steps over the keyword name — deliberately, so the
name is not parsed as an expression and reported as an undefined variable — and
its own comment records the assumption:

```pascal
      { NilPy `name=expr`: step over the keyword before probing, or the name is
        parsed as an expression and reported as an undefined variable — an
        OVERLOADED façade method could not be called with keyword arguments at
        all (`canvas.create_window((0,0), window=w)`). The probe only needs the
        argument's TYPE; which parameter it binds to is settled later by
        PyKwArgIndex. }
```

That is true of what the two loops below it want to know and **false of how
they index**, which is positional — `Procs[pi].Params[base + j]`. So for
`meth(a=0, v=(8,6))` against `meth(a: Integer; s: AnsiString; v: Variant)`,
argument 1 is judged against **`s`**, a reference-shaped argument lands on a
string slot, the guard fires, and a legal call is refused.

Predicted from the code, then measured before any edit. Every row of the
ticket's boundary table follows from it, including why the constructor and the
unit-level procedure pass: different paths, no probe.

| shape | predicted | measured |
| --- | --- | --- |
| tuple's positional slot is `s` (AnsiString) | refuse | FAILS |
| tuple's positional slot is `a` (Integer) | refuse | FAILS |
| no gap — tuple lands on its own Variant slot | bind | OK |
| scalar argument (not reference-shaped) | bind | OK |

### The second exposure, which is the more serious half

The **ranking** loop indexes positionally too. With more than one candidate, an
overloaded method called with keywords that skip a default is ranked against
the wrong parameters — that is silent wrong-overload selection, not a
diagnostic. Same root, so one fix closes both; a fix aimed only at the reported
symptom would have repaired the refusal and left the silent one in place.

### The fix

A helper `OverloadArgParamIdx(pi, base, j, kwTok)` resolves argument `j` to its
declared parameter: `base + j` when positional, and the named parameter when the
argument was `name=`. The probe now **records** the keyword name as a token
index instead of discarding it, and both loops index through the helper.

It **abstains** (returns -1, callers skip that argument) when the name matches
no declared parameter, because a callee with `**kwargs` legitimately takes it —
and an abstention can only ever drop a check, never manufacture a refusal. That
is this file's own standing rule: an unsound refusal of a legal program is worse
than the looseness it replaces. A wrong keyword name is still rejected, by
`PyKwArgIndex`, with its proper diagnostic.

### Verification

New gated test `test_nilpy_keyword_call_tuple_on_a_skipped_default.npy` with
`kwpadprobe.pas`, a facade shaped like `grid()` — ordinal, then **string**, then
Variant, so a skipped option lands the tuple on the string's slot. It is
**verified to fail on the baseline** (`no overload of grid matches these
arguments`) as well as pass here.

**Both halves are asserted**, which is the point of the test rather than a
flourish. The refused shapes *and* the accepted ones (`sticky` supplied, no gap)
are pinned, because a fix repairing the refusal while breaking its neighbour
would pass any test that only watches the failure — and songformatter grids two
identical widgets nine lines apart, one of each. Also pinned: a leading
positional argument then keywords, scalars, lists, and the free-procedure
control that never runs the probe.

Attribution measured against **HEAD-without-this-patch** (`f8f879988222`) rather
than an older sha, both compilers built from the same base.

### Songformatter

`settings.py` **compiles** — both line 178 (accepted) and line 183 (refused).
`key_analysis.py` compiles. `convertrawtext.py` and `SongFormatter.py` now reach
a later, unrelated wall reported at `key_analysis.py:82`; that one is
**pre-existing and not from this fix** — with the tuple-pad trigger removed from
a copy of the app so the baseline can reach the same depth, `f8f879988222` hits
the identical failure. Filed separately.

### Gate

`make compiler/pascal26` fixedpoint `bcb428ba25ac`; **`tools/gate.sh quick`
GREEN** (A's gate, as the grant requires — this is Pascal-frontend ground shared
with Track A, so the fixedpoint alone is not sufficient).

## Log
- 2026-08-30 — resolved, commit 51b0753e7.
