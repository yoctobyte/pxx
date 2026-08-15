---
track: N
prio: 35
type: bug
blocked-by: []
summary: "Redefining a `def` makes calls written BEFORE the redefinition run the LATER body. `def q: 'first'; print(q(1)); def q: 'second'; print(q(2))` prints second/second where CPython prints first/second. Silent wrong value on a valid CPython program, and there is no diagnostic — the name resolves once, statically, to the last definition."
---

# Redefining a `def` rebinds the calls that came before it

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-15, and found the hard way: an appended test block reused a
  helper name the file already had, and the EXISTING rows above it started
  printing binary garbage
  ([[bug-nilpy-star-unpack-that-would-fill-a-fixed-parameter]]). Reproduced on
  `pinned`, so it is pre-existing and independent of that work.

## Repro

```python
def q(a):
    return "first:" + str(a)
print(q(1))            # CPython first:1     pxx second:1
def q(a):
    return "second:" + str(a)
print(q(2))            # CPython second:2    pxx second:2
```

No diagnostic. The name resolves once, statically, to the LAST definition in
the module, so every call site — including the ones lexically above the
redefinition — targets it.

## Why it is worse than it reads

With the same signature it is a wrong VALUE. With a **different** signature it
is memory corruption: the case that surfaced it had

```python
def g(x, *rest):
    return str(x) + "|" + str(rest)
print(g(1, *xs))       # bound, at run time, to the LATER g...

def g(x, *rest):
    return x, rest     # ...which returns a TUPLE, not a str
```

and the earlier call — compiled expecting a string result — printed several
kilobytes of raw memory. So the failure mode is not bounded by "you get the
other function's answer".

## In scope under the upward-compatibility rule

Redefinition is ordinary CPython that runs to completion and observably differs,
so this is not the "laxer than CPython is a feature" case
(`devdocs/dev/nilpy-semantics-divergences.md`). It is the mirror of
[[project_nilpy_trial_parse_rolled_back_symbol_index_recycled]]'s family: one
NAME, two bindings, and the frontend keeps only the last.

## Shape a fix probably takes

NilPy names are resolved statically, so the fix is at DEFINITION time, not call
time: a second `def` of an existing name should allocate a NEW proc and rebind
the name from that point in the parse forward, leaving already-parsed call sites
pointing at the first. That is how the shadowing rules elsewhere in this
frontend work, so the machinery is likely present.

Worth checking in the same pass whether a `class` redefinition, and a `def`
that shadows an imported name, have the same shape.

## Gate

`.npy` diffed against CPython: same-signature redefinition with calls on both
sides; different return TYPE (the corrupting case above); a redefinition inside
a branch that does not execute; and a `class` redefined the same way. Per-fix
loop.

## 2026-08-15 — mechanism located, PARKED (not started)

Found the exact site and, more usefully, found that this is the **overshoot of a
shipped fix for the opposite bug**. That changes what a safe fix looks like, so
it is recorded before anyone starts.

`PyParseDef` (`compiler/pyparser.inc` ~26072):

```pascal
procIdx := FindProcInUnit(name, -1);
if procIdx < 0 then procIdx := FindProc(name);
if (procIdx >= 0) and (Procs[procIdx].BodyAddr >= 0) and
   (Procs[procIdx].ParamCount = nparams) then
begin
  { ...overwrite the FIRST proc's signature, and later its body... }
```

A same-arity redefinition deliberately **reuses the first def's Proc**. Its own
comment says why, and cites the ticket it fixed:

> a second same-arity Proc is one no call site can ever reach, and every call
> kept running the FIRST body forever
> (`bug-nilpy-redefining-a-def-is-ignored-the-first-body-still-runs`)

So the two failure modes are the two ends of one lever: give the redefinition
its own Proc and *no* call reaches it; reuse the first Proc and *every* call
reaches the second body, including the ones written above it. **Both are wrong,
and a fix that only moves the lever back re-breaks the shipped ticket.** That is
the whole reason this is parked rather than attempted.

What CPython actually does is neither: `def` is an assignment executed where it
stands, so the binding is **positional** — calls above see the first body, calls
below the second. Two Procs AND a rebinding at the def's position.

**The constraint that makes it non-trivial:** `PyRegisterDefShells` is a
PRE-PASS that registers every module-level def before any body is parsed, and
`FindProc`'s hash chain answers the OLDEST registration for a name. So "which
registration is current" cannot be read off the symbol table at all — it needs a
per-name cursor advanced as the main parse passes each `def` statement, which
call-site resolution then consults. That is a change to NilPy name resolution,
in the one spot with a documented history of regressing in both directions (the
same block also carries a `def len(x)` builtin-shadowing fix).

**Do not take this as a between-tasks item.** It wants the full sibling set green
in one go: redefinition with calls on both sides, differing arity (the existing
separate-Proc path, which must keep working), a def shadowing a pylib builtin,
and a nested def's qualified name.
