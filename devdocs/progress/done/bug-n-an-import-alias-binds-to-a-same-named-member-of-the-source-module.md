---
track: N
prio: 85
type: bug
blocked-by: [decide-how-a-compiled-def-carries-its-signature-when-boxed]
summary: "RE-SCOPED: not about import aliases. A name that names a `def` is resolved to that def at EVERY call site and any later rebinding is ignored — `def a…; def b…; b = a; b(1,5)` answers 18 (the original b) where CPython answers 5, with no import anywhere. The alias spelling is one way to rebind. Blocked: the correct destination is the dynamic call path, which cannot yet carry defaults (see the decision ticket)."
status: done
owner: frankA
---

# An import alias binds to a same-named member of the SOURCE module

- **Type:** bug (name binding) — **Track N** (Nil-Python frontend)
- **Found:** 2026-08-18 by frank2-7e while reproducing
  [[bug-n-a-default-argument-is-dropped-on-every-cross-module-call]]; the
  defaults-free row was pointed out by the coordinator and re-measured here.
- **Measured at:** HEAD, self-host fixedpoint build, differential against
  CPython running the same file unmodified.

## Repro — no defaults involved

`mmod.py`:

```python
def f(a, lo=7):        return lo
def g(a, lo=3, hi=13): return lo + hi
class C:
    def m(self, a, lo=7): return lo
```

```python
from mmod import f as g
print(g(1, 5))      # pxx prints 18   -- CPython prints 5
```

**Every argument is supplied.** No default applies. `18` is `5 + 13`, i.e.
`mmod.g(1, 5)` — the alias bound to the module's own `g` instead of to `f`.

| call | pxx | CPython | |
| --- | --- | --- | --- |
| `from mmod import f as g; g(1, 5)` | **18** | 5 | **DIVERGES — no defaults involved** |
| `from mmod import f as g; g(1)` | **16** | 7 | DIVERGES |
| `from mmod import f as zz; zz(1, 5)` | 5 | 5 | ok — fresh alias name |
| `from mmod import f as C; C(1, 5)` | **a C instance** | 5 | **DIVERGES — constructs M's class** |

The last row is the worst shape: aliasing to a name that is a CLASS in the
source module silently **constructs that class** instead of calling `f`.

## Why this is filed separately from the p90 defaults bug

It is **not** a symptom of
[[bug-n-a-default-argument-is-dropped-on-every-cross-module-call]], and the
top row proves it: all arguments supplied, no default path reached, still
wrong. The two were entangled because the alias ticket's original repro
omitted a default, so both defects fired at once and the crash was read as a
dereferenced dropped default. It is really a call landing on a **different
function with a different signature**.

Filed BEFORE the defaults fix lands, deliberately: once that lands the
fresh-name alias row goes correct while the colliding row stays wrong, and a
reader seeing a half-fixed alias ticket at that moment would mis-diagnose it.

This also means the defaults fix will **not** retire
[[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]] —
that ticket's repro uses a colliding alias name, so its crash is this bug.

## What to check when fixing

`from X import a as b` must bind `b` in the IMPORTING module's namespace only,
to whatever `a` names in X. The alias name must never be looked up as a member
of X. Verify by value against CPython for: an alias colliding with a function
in X, with a class in X, with a variable in X, an alias that shadows a name in
the importing module, and two aliases crossing over
(`from X import a as b, b as a`).

## RE-SCOPED AND BLOCKED 2026-08-18 (frank2-7e)

Measured at HEAD `4e823d0d2`, self-host fixedpoint, differential against CPython.

### It is not about import aliases

The same failure appears with no import anywhere — a plain **same-file**
rebinding of one `def` name to another function:

```python
def a(x, lo=7):        return lo
def b(x, lo=3, hi=13): return lo + hi
b = a
print(b(1, 5))        # pxx 18 (the ORIGINAL b) -- CPython 5
```

| shape | pxx | CPython |
| --- | --- | --- |
| `from M import f as g; g(1,5)` | 18 | 5 |
| `from M import f, g` then `g = f; g(1,5)` | 18 | 5 |
| **`def a…; def b…; b = a; b(1,5)`** (no import at all) | **18** | 5 |

So the rule is: **a name that names a `def` is resolved to that `def` at every
call site, and any later rebinding of the name is ignored.** An import alias is
one way to rebind a name; it is not the cause. In Python a `def` binds a name in
a namespace and assignment replaces the binding, which is what makes decorators,
monkey-patching and swap-in test doubles work.

The class row from the original report is the same rule seen through a class:
`from M import f as C` leaves `C` naming M's class, so `C(1,5)` constructs it.

### BLOCKED on the callable-signature decision — measured, not assumed

The correct destination for a rebound name is the **dynamic call path**
(`pyvar_callv<n>`), which is what already makes a fresh alias `zz = f; zz(1,5)`
answer 5 correctly. But that path is exactly the one diagnosed in
[[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]]:

```
from M import f as zz;  zz(1)   ->  empty, exit 0    (CPython 7)
handlers[0](1) / d["x"](1) / fn(1) / bound method   ->  SIGSEGV
```

So routing rebound names through it *today* would fix the all-arguments-supplied
rows and turn the omitted-default rows from a wrong value into **a wrong value or
a crash** — a regression in kind, and precisely the "green test certifying a
hole" shape this campaign has now hit twice.

**Therefore this ticket is blocked on
[[decide-how-a-compiled-def-carries-its-signature-when-boxed]]** (U, p88). Once a
callable value carries its signature, routing a rebound name through the dynamic
path becomes correct and this becomes a tractable frontend change.

### What the fix looks like once unblocked

A pre-pass fact, not a call-site guess: record module-level names that name a
`def` **and** appear as an assignment target anywhere in the module; resolve calls
to those names through the variable rather than to the proc. Names never rebound
keep today's direct call, so the common path costs nothing. NilPy already runs
pre-passes over its own token span (`ParsePyUnit`), which is where the fact
belongs.

Not attempted: it would be built on a dynamic path that cannot yet carry
defaults, and the whole point of the decision above is which representation fixes
that.

### Retitling

The title names the alias shape, which is one instance rather than the rule. Left
to whoever takes it, same convention as the other two tickets re-scoped today.


---

**Unblocked and moved to `backlog/` by the coordinator, 2026-08-28.** Its declared
`blocked-by` names a ticket that has since been resolved, so this was sitting in `blocked/` —
which `ready`/`next` never scan — while it was actually rankable. Nothing about the work
changed; only the record was stale. Found by a sweep (see
`chore-t-nothing-re-checks-a-blocked-by-edge-after-its-blocker-closes`); 14 tickets repo-wide
carry at least one `blocked-by` naming a closed ticket, five of them fully unblocked.

**SUPERSEDED 2026-08-29 — Track N IS being dispatched again.** The paragraph below
was correct when written and is kept so a reader meets it where it was relied on.

> ~~**Track N is NOT being dispatched** (owner deprioritized it and reserved the call, 2026-08-27).
> This ticket is rankable again and correctly filed, but do not auto-claim it on a cold-start
> "take the global top" — ask the owner first.~~

The owner lifted it, 2026-08-29, verbatim: *"track A+C+P+N is highest prio at all
times and the hardest to parallelize. having track A idling is a waste of time and
tokens."* N is named explicitly in the highest-priority set, and the statement is
two days newer than the reservation it replaces. **Claim it normally.**

Recorded by the coordinator rather than left in message traffic: the reservation
was durable prose on master and its lifting has to be too, or the next agent
re-reads the ticket and re-refuses. frankA declined this dispatch on the strength
of the old paragraph and was right to — the paragraph was the only thing on master
that spoke to it.

## MEASURED AT HEAD 2026-08-29 — the 2026-08-18 re-scoping is STALE, the TITLE was right

Re-measured against CPython before touching anything. Two premises above no
longer hold, and both would have sent the next reader the wrong way.

**1. The re-scoping is stale.** The section above says the failure "appears with
no import anywhere" and gives `def a…; def b…; b = a; b(1,5)`. That case
**passes at HEAD** — pxx 5, CPython 5. Locally-`def`'d names now rebind
correctly. So the defect really is the import one the TITLE names, and the
generalisation to "a name that names a `def` is resolved at every call site"
is no longer the rule.

**2. `blocked-by` is satisfied and its stated reason is gone.** The block was
that the dynamic call path "cannot yet carry defaults", evidenced by
`from M import f as zz; zz(1)` printing empty. At HEAD that prints **7**, which
is CPython's answer. The decision ticket is in `decided/` and the measurement
that motivated the block no longer reproduces.

### The table, re-measured, before -> after

| shape | before | after | CPython |
| --- | --- | --- | --- |
| `from M import f as g; g(1,5)` | 18 | **5** | 5 |
| `from M import f as g; g(1)` | 16 | **7** | 7 |
| `from M import f as g, g as f` | `5 5` | **`5 18`** | `5 18` |
| `from M import f as C; C(1,5)` | a C instance | **5** | 5 |
| `from M import f as zz; zz(1,5)` | 5 | 5 | 5 |
| `from M import f, g` (plain) | 5, 18 | 5, 18 | 5, 18 |
| **`from M import f, g; g = f; g(1,5)`** | 18 | **18** | 5 |

Three defects, not one — which is why the first fix could not close it:

- **the call site** preferred an imported proc over a module-level binding;
- **the import parser** resolved an alias's SOURCE name with a flat lookup, so
  `g as f` found the `g` that `f as g` had allocated an instant earlier
  (CPython binds every name of one from-import from the source module
  simultaneously);
- **the constructor path** is a SECOND mechanism for one concept —
  `PyIsExactCtorName` decides `Name(` is a construction without consulting any
  binding, so `f as C` constructed M's class. Fixing the call site alone leaves
  this one live, and it looks fixed from the ticket's first row.

### STILL OPEN — one row, and it is not dropped

`from M import f, g` then `g = f` still answers 18. Catching it needs a
module-level assignment scan keyed by NAME, which is `PyDefRebindTok`'s job in
`compiler/symtab.inc` — **Track A's file, held by another agent**, so it was not
taken. Filed here rather than silently omitted: the table is the only record
anyone rereads, and a row removed from it reads as passing.

### A regression I caused, and the reason it is recorded here

The first fix (`15335c82c`) broke `test_nilpy_fallback_import_try_wins` and was
repaired in `46b2439c4`. The rule was "a module-level var declared in this unit
beats a proc from another unit" — true for a **rebinding**, false for a **plain
import**, because an optional (`try:`) import allocates a module-level var for
the plain spelling too, so a real import binding was shadowed by None.

**Every one of this ticket's seven rows still passed. The eighth shape, the one
not in the table, is what broke.** That is a scope error, not a reasoning error,
and the table looked complete — which is the same failure as reading a sample as
a census. An enumeration treated as exhaustive and a sample treated as a census
are one defect wearing two hats: *the instrument's scope is invisible in its own
output, and the scope is exactly where the next defect lives.*

The practical consequence for whoever takes the remaining row: **the table above
is not the specification.** Before landing a change to name binding, check at
least one shape that is not in it — an optional import, a conditional import, a
name bound by both a def and an import.

## WARNING for the remaining 2 shapes: the first 5 broke fallback-import, and it is not obvious why

`15335c82c` fixed 5 of the 7 divergent shapes here and, in doing so, regressed
`test_nilpy_fallback_import` and `test_nilpy_fallback_import_try_wins`. Bisected
on host `seven` 2026-08-29, self-hosted compiler rebuilt at each sha (`converged
after 2 round(s)` throughout), running the recipe's own `-Futest/nilpy_units`:

| sha | result |
| --- | --- |
| `7b8f0afc5` (parent) | `hello fallback` / `hello try branch` |
| **`15335c82c`** | `TypeError: object is not callable — the name is None` |
| `2d65e9c45` (HEAD, after the follow-up fix) | `hello fallback` / `hello try branch` — **repaired** |

Both regressions are closed; this note is not about them. It is about the
**sixth shape**, which the precedence rule has now demonstrably reached once:

`try: import X / except ImportError:` selects its branch at **compile** time
(`Makefile:1127`). So the except branch's module-level assignment and the
imported name **share a spelling by construction** — that is what the feature
IS (`done/feature-nilpy-fallback-import`). Any rule deciding "module-level
binding vs imported name of the same name" therefore governs fallback-import
whether or not it was written with that case in mind, and the failure it
produces is silent: the name binds to `None` and the program dies later at the
call site, naming neither the import nor the rule.

**Before finishing shapes 6 and 7, run those two tests with
`-Futest/nilpy_units`.** They are the cheapest available oracle for this rule's
blast radius, they are not in the quick tier, and a bare invocation without that
flag reports a *different* failure (`import: no unit named pkgprobe_sub`) that
looks like an unrelated resolution bug — which is how it first got mis-recorded.

Recorded by the Track T agent on `seven` under the provenance rule: my box's
sweep produced the regression, so the narrowing is mine to leave behind. The
rule itself is Track N's.
> **ANSWERED — frankA, 2026-08-29.** Done, before reading this note, and the
> answer is clean. Both named tests plus four more import-shaped ones were run
> with `-Futest/nilpy_units` against the pinned baseline and against the tree
> carrying BOTH agents' fixes, and every one is **byte-identical**:
> `fallback_import`, `fallback_import_mixed`, `fallback_import_try_wins`,
> `bare_import_is_python`, `dotted_import`,
> `class_named_after_its_imported_base`.
>
> The warning's other half was also worth its length: a bare invocation without
> `-Futest/nilpy_units` **does** report an unrelated-looking failure, and it cost
> me a false alarm before I ran the baseline. I read six build failures as
> regressions from my own change; the pinned compiler produced the same six. The
> flag is the difference, exactly as recorded here.
>
> The rule that landed is narrower than the one that caused the earlier
> regression, which is likely why fallback-import is untouched: it does not say
> "a module-level var beats an imported proc". It says the module-level
> ASSIGNMENT that rebinds the name must be found even when the def lives in
> another unit's region of the shared token array — an ordering test, still
> gated on an assignment actually existing at depth 0 in this module. A plain
> optional import allocates the var without assigning at module level, so it
> never satisfies it.

---

> **CONCURRENCY NOTE — frankA, 2026-08-29.** The section above and the one below
> are **two agents fixing this ticket at the same time, neither able to see the
> other.** Both are kept, in the order they landed. The split is clean and almost
> comically complementary: the other agent could not take the last row because
> `PyDefRebindTok` lives in `compiler/symtab.inc`, **Track A's file, held by me** —
> and that row is the only one I fixed, because I had A. Meanwhile I split the
> class-constructor and crossing-alias rows out as unreachable from the proc arm,
> which is exactly what the other agent had already fixed.
>
> Nothing here is contradictory, but the two accounts diagnose *different*
> mechanisms and each is right about its own. Read them together: theirs covers
> the call site, the import parser's simultaneous binding, and the constructor
> path; mine covers the cross-unit token scan and the alias's tokenless
> synthesised assignment. The combined result is re-measured at the bottom.
>
> The follow-on ticket I filed
> (`bug-n-an-import-alias-cannot-shadow-a-class-or-cross-with-another-alias`) is
> **obsolete on arrival** for both of its rows and is withdrawn to `rejected/`
> with a pointer here.

---

## RESOLVED 2026-08-29 (frankA) — and the 2026-08-18 re-scope was WRONG

Taken after the coordinator relayed the owner's lifting of the Track N
reservation (the superseded paragraph above). Measured first, differential
against CPython on every row, before reading the analysis below it — which is
how the following came out.

### The re-scope is stale: the same-file rows now PASS

The section above concludes *"a name that names a `def` is resolved to that
`def` at every call site, and any later rebinding is ignored"*, and offers the
import-free program as proof:

```python
def a(x, lo=7):        return lo
def b(x, lo=3, hi=13): return lo + hi
b = a
print(b(1, 5))         # recorded: pxx 18, CPython 5
```

**At HEAD that prints 5.** It was fixed in the meantime by
`bug-n-a-module-level-rebinding-still-loses-to-a-def-of-the-same-name`, whose
`PyDefRebound` is the machinery this ticket then reuses. So the generalisation
that renamed this ticket was true when written and is no longer, and the
**original title was right all along**: what survived is import-specific.

Worth stating because the re-scope was a *reduction* — the good kind of move —
and it still went stale. A ticket re-scoped by measurement carries a
measurement's shelf life.

### Root cause: `Tokens[]` is ONE array shared by every unit

The rebinding rule was already correct; it just could not see across a unit
boundary. `PyDefRebindTok` scans forward from `ProcPyDefTok[pi]` for a depth-0
`name =`. A NilPy import **appends** the module's tokens after the program's, so
for an imported def that index points into the *other* unit's region:

```
PROBE g: procIdx=1856 idx=471 pydeftok=205755 rebindtok=-1 rebound=0
         tokpos=28 procunit=637 curunit=-1 tokcount=205801
```

The def sits at token **205755** of **205801**; the rebinding is at token **28**,
*behind* it. The scan had 46 tokens of another unit's tail to look at and
correctly found nothing. **A def's position does not order the statements of a
different module** — so when the units differ the scan now starts at the top of
the stream, where the module being compiled is, and is not cached (the answer
depends on which unit is being compiled, and there is one slot per proc).

Same-unit lookups — every NilPy program that never imports — keep the cache and
the old path byte for byte.

### The second mechanism: an alias's rebinding has NO TOKENS

`from M import f as g` is a real binding — `PyFlushImportAliases` emits
`g = f` into the module body — but it is **synthesised**, so a token scan can
never find it however it is aimed. That needed a separate record:
`ProcPyAliasRebindTok`, stamped at the import's own token for every proc on the
chain named by the alias, and consulted by `PyDefRebound` when the scan comes
back empty. Deliberately NOT folded into `ProcPyRebindTok`, which caches a scan:
one array must not mean both "computed and cached" and "explicitly recorded".

Stamped only for a genuine rename (`impAlias <> impReal`) — `from M import g`
binds the name to the proc it already meant, and stamping that would unbind a
name nothing rebound. That is the `H` control below.

### Verified — every row, against CPython

| shape | before | after |
| --- | --- | --- |
| `from M import f as g`, `g(1)` | 16 | **7** |
| `from M import f as g`, `g(1, 5)` | 18 | **5** |
| `from M import g`, then `g = <local def>` | 16 | **99** |
| `from M import f, g`, then `g = f` | 18 | **5** |
| **H** `from M import g`, no rebinding | 16 | 16 (unmoved) |
| a call written ABOVE the import | — | correct (ordering kept) |
| fresh alias `f as zz` | 5 | 5 (unmoved) |
| same-file `b = a` | 5 | 5 (unmoved) |
| `from M import g`, `g = 42`, `print(g)` | 42 | 42 (unmoved) |

Regression test `test/test_nilpy_import_alias_collides.npy` + fixture
`test/nilpy_aliasmod.py`, wired into the Makefile. It prints `7 5 2 99 7` on the
fix and `16 18 2 2 14` on the pinned baseline — **run the baseline; a test that
passes on both proves nothing.** Row 3 of it is an ordering control: the
rebinding below has not run yet, so that call must still reach the import.

### A blind probe, recorded because it nearly cost the diagnosis

`print(type(g))` answered `NoneType` in pxx and `<class 'function'>` in CPython,
which read as "the assignment never landed" and pointed at the wrong mechanism
entirely. It was the **control** that killed it: the same probe answers
`NoneType` on the rows that WORK, so `type()` of a function value is simply
unimplemented and the probe could not distinguish anything. Running it on a
known-good case cost ten seconds and saved the wrong root cause.

### NOT fixed here — split out, not forgotten

Two rows of the table above need different mechanisms and are filed as
[[bug-n-an-import-alias-cannot-shadow-a-class-or-cross-with-another-alias]] (N,
p60):

- **`from M import f as C` where M has a CLASS `C`** still constructs it. The
  stamp walks the PROC chain and a class is not on it; `FindUClass` consults the
  alias table only *after* the real class scan succeeds, so a shadowing row
  there is unreachable by construction. Needs a "this name is not a class here"
  concept tested before the scan — a real change to a resolver with many callers.
- **`from M import f as g, g as f`** answers `5 5` where CPython answers `5 18`:
  crossing aliases must both read the pre-import bindings. That is a
  simultaneity question in `PyFlushImportAliasesFrom`'s drain order, not a
  resolution question.

Both were rows of this ticket; neither is a variation of the arm that landed, so
splitting beat a partial claim.

### Gate

`make compiler/pascal26` — `converged after 1 round(s)`, fixedpoint
`e55fdee01ac5`. `tools/gate.sh quick` green, including the FPC seed / forward-decl
step the coordinator has since wired into it.

## Log
- 2026-08-29 — resolved, commit b25e3ac49.

> **INDEPENDENT VERIFICATION of the combined fix — pxx-a5, 2026-08-29.** I had
> built a duplicate of the rebind row (`PyNameRebindTok` in `pyparser.inc`, a
> name-keyed token scan) before learning frankA had already landed it in
> `symtab.inc` at `b25e3ac49`. **Discarded unpushed rather than merged** — two
> mechanisms for one concept is the defect this ticket already contains three
> instances of, and adding a fourth to avoid wasting an hour's work would have
> been the worst possible trade.
>
> It was not wasted, because building it produced two shapes that were in
> neither account, and re-measuring them against frankA's fix at `650034e60`
> confirms it handles both:
>
> | shape | pxx | CPython | |
> | --- | --- | --- | --- |
> | `from M import f, g` / `if False: g = f` / `g(1,5)` | 18 | 18 | conditional rebinding must NOT count |
> | `from M import f, g` / `g(1,5)` / `g = f` | 18 | 18 | a rebinding below the call has not run |
>
> Both matter for upward compatibility: the first program is legal in CPython
> and the import must survive a branch that never runs. All seven rows verified
> green at `650034e60` with no local changes.
