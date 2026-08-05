---
track: P
prio: 45
type: bug
summary: "RequireRecMember has 3 call sites, all expression paths, and ~20 AN_FIELD construction sites exist. A breakpoint proved the statement-LVALUE path never calls it. No longer a silent wrong store (RecFieldType now rejects), but the guard is inconsistent and its coverage is unaudited."
status: done
owner: claude-A
---

# The member check is missing on the statement-lvalue field path

- **Type:** bug (missing diagnostic / inconsistent guard) — **Track P**
  (member resolution, shared `parser.inc`)
- **Opened:** 2026-08-03 by claude-P@opus5 as the deliberate remainder of
  [[bug-pascal-unknown-record-field-accepted-in-compiler-source]].
- **Not urgent:** the silent-wrong-store half is fixed. This is the consistency
  half.

## Measured

`RequireRecMember` (`parser.inc:3612`) has exactly **three** call sites —
`parser.inc:6176`, `7421`, `7589` — and all three are expression paths. There
are ~20 `AllocNode(AN_FIELD)` sites.

A breakpoint on the guard, running the compiler over a tree containing
`Syms[0].Bogus := -1`, was **never hit**: the statement-lvalue path builds its
`AN_FIELD` without ever consulting it. That was measured with a `-g` compiler
and gdb, not inferred.

## Why it is no longer producing wrong values

The parent bug's fix rejects at the point the miss is *decided*, inside
`RecFieldType`'s builtin-record branch. That is path-independent, so it catches
the lvalue path too — for **builtin-mirrored** records.

For a **user** record (`recId >= REC_UCLASS_BASE`) reached purely through the
lvalue path, the guard is still not called; whether a bad member is caught then
depends on other checks downstream. No repro is known that gets through — four
minimal shapes are all correctly rejected — which is precisely why this is an
audit rather than a bug report with a failing case attached.

## The work

1. Enumerate the ~20 `AllocNode(AN_FIELD)` sites and classify each: expression
   vs lvalue, and which frontend it serves.
2. Add `RequireRecMember` to every Pascal path that lacks it. It is safe by
   construction on the sites that do not need it — it no-ops unless
   `recId >= REC_UCLASS_BASE` and `FindUField` misses.
3. **Do not add it blind to NilPy paths.** `parser.inc` is shared, and NilPy
   objects have dynamic attributes, so a member miss there can be legitimate.
   Gate on `not isNilPy` where a shared site serves both.
4. Consider collapsing the three existing call sites and the new ones into the
   single place the field's type is resolved, so the count cannot drift again —
   the same argument the parent bug's fix used.

## Gate

An unknown member on a user record errors identically whether it is written as
an lvalue (`r.nope := 1`), read in an expression (`x := r.nope`), or passed as
an argument; NilPy dynamic attribute access is unaffected (`test-nilpy` green);
self-host fixedpoint byte-identical; `gate.sh quick` green.

## Audited 2026-08-05 — no gap remains; closing on evidence, with no code change

**The ticket's own gate is met.** An unknown member on a USER record errors
identically however it is written:

| form | |
| --- | --- |
| `r.nope := 1` (lvalue store) | rejected |
| `x := r.nope` (expression) | rejected |
| `Take(r.nope)` (argument) | rejected |
| `writeln(r.nope)` | rejected |
| `r.nope := r.nope + 1` (both sides) | rejected |
| `Inc(r.nope)` | rejected |
| `r.a := 1` (valid member, control) | accepted |

Extended past the gate to every lvalue shape that reaches `AN_FIELD` by a
different route — the audit item 1 asked for, done by behaviour rather than by
counting sites:

| lvalue shape | |
| --- | --- |
| nested record `r.inner.nope := 1` | rejected |
| static array element `arr[0].nope := 1` | rejected |
| pointer deref `p^.nope := 1` | rejected |
| class field `c.nope := 1` | rejected |
| `with r do nope := 1` | rejected |
| dynamic array element `dyn[0].nope := 1` | rejected |
| `var` parameter `q.nope := 1` | rejected |
| valid nested `r.inner.b := 1` (control) | accepted |

**NilPy dynamic attributes are unaffected** — item 3's constraint. `c.y = 2` on
an instance that never declared `y` still compiles and prints, verified.

### Why the ticket's measurement is stale

It recorded **three** `RequireRecMember` call sites and a breakpoint that was
never hit on the lvalue path. There are now **four**. The deduction needs no
instrumentation: `RecFieldType` errors only in its BUILTIN-record branch — a
user record whose field misses simply returns `tyUnknown` there — yet
`r.nope := 1` on a user record IS rejected. So the lvalue path must now reach
`RequireRecMember`. Something closed it between the ticket being written and
now.

### What is deliberately NOT done

Item 4 — *"consider collapsing the call sites into the single place the field's
type is resolved, so the count cannot drift again"*. It is a `consider`, it is a
refactor of working code with no behavioural gap left to justify it, and the
count it guards against (4 sites vs 27 `AllocNode(AN_FIELD)`) is a code-shape
observation, not a defect. Filed thought, not filed ticket: if it is wanted, it
wants its own change with its own gate, not a rider on an audit.

**No code changed**, so no gate was run beyond the measurements above — there is
nothing to regress.

## Log
- 2026-08-05 — resolved, commit PENDING-COMMIT.
