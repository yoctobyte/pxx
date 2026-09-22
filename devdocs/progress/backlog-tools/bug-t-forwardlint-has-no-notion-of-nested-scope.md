---
slug: bug-t-forwardlint-has-no-notion-of-nested-scope
title: "`forwardlint.py` flags a NESTED routine against an unrelated local variable of the same name"
track: T
prio: 30
type: bug
status: backlog
created: 2026-09-22
owner: ""
summary: "tools/forwardlint.py collects every `procedure NAME` in the include chain INCLUDING NESTED ones, with no notion of scope, and then flags any earlier TEXTUAL occurrence of that identifier -- call, variable, parameter or field alike. So a nested routine named generically is reported as an FPC-seed forward-reference violation that cannot exist, because a nested routine is not visible outside its parent. Measured 2026-09-22: a nested `procedure Mark` in dce.inc was reported against `while PyPendLamCount > mark do` in pyparser.inc, 38k lines earlier, where `mark` is a LOCAL VARIABLE and the line contains no call at all. The lint is otherwise doing real work and this is not a reason to weaken it -- the FPC-seed hazard it guards is real and has bitten twice in ir_codegen_wasm32.inc -- so the ask is scope awareness or a documented naming rule, NOT a looser match. Worked around at the call site by renaming the nested routines, which is why nothing is red today."
---

# What

`tools/forwardlint.py`'s `analyse()` is a two-pass flat identifier scan:

```python
for pos, (_path, _ln, code, _cond) in enumerate(stream):
    m = DEF.match(code)
    if m:
        declared.setdefault(m.group(1).lower(), pos)
```

`DEF` matches a `procedure`/`function` declaration **wherever it appears**,
including one nested inside another routine's declaration part. The second pass
then walks every identifier on every earlier line and reports any that resolves
to a later declaration.

Nothing distinguishes a *call* from any other occurrence of the identifier, and
nothing tracks scope. So the report fires on:

- a nested routine's name colliding with a **local variable** elsewhere
- a nested routine's name colliding with a **parameter**, a **field**, or a
  **record member** elsewhere
- any of the above even when the two are in files that cannot see each other

# The measured instance

Adding a nested `procedure Mark(slot: Integer)` inside `WasmDceRun`
(`compiler/dce.inc`) produced:

```
FAIL /home/neo/frankB/compiler/pyparser.inc:38397: calls mark,
     declared at /home/neo/frankB/compiler/dce.inc:812,
     which FPC has not seen yet
```

`pyparser.inc:38397` is:

```pascal
  while PyPendLamCount > mark do
```

`mark` there is a local variable. The line contains no call. And the reported
declaration is nested inside another routine, so it is invisible to every line
in the file the lint is pointing at — under FPC *and* under pxx. The build
self-hosted fine (`converged after 1 round(s)`) both before and after the
rename; only the lint objected.

# What this is NOT

**Not a reason to loosen the lint.** Its header states the hazard it exists
for and it is real: *"pxx resolves names across a whole unit; FPC — the
bootstrap seed — resolves them in SOURCE ORDER. So a file can self-host
perfectly and still break the seed build."* It has caught that twice in
`ir_codegen_wasm32.inc`. A false positive here is cheap; a false negative
costs a seed build, and those are found by `gate.sh quick`'s FPC canary once at
the end of a phase.

So the failure mode this ticket is about is the *other* one CLAUDE.md names:
**a guard that cries wolf on a case its author did not intend teaches that it
can be ignored.** The next person to hit this may reach for the wrong lever.

# Options, in the order I would rank them

1. **Skip nested declarations.** Track `procedure`/`function` nesting depth
   while scanning — a declaration inside another routine's declaration part is
   not a unit-level name and cannot be forward-referenced from elsewhere. This
   is the correct fix and it narrows nothing the lint legitimately catches.
2. **Require the occurrence to look like a call or a reference**, i.e. not
   immediately preceded by `var`/`:`/`.`, and not a bare operand in a
   comparison. Weaker, more heuristic, and it would still fire here (`> mark`
   is a bare operand, which is exactly what it would have to learn to ignore).
3. **Document a naming rule** — nested routines take a distinctive prefix —
   and leave the lint alone. Cheapest, and it is what the call site does today,
   but it is a rule nobody will find until the lint fires at them.

I did not implement (1) because `forwardlint.py` is Track T's file and the lint
is load-bearing for every lane's seed build; a change to it wants its own
positive control (a real forward-reference violation it must still catch)
rather than a drive-by from a Track A fix.

# Current state

Not red. The nested routines in `dce.inc` were renamed to `WasmDceMark` /
`WasmDceMarkProc`, with a comment recording why the generic name was wrong
there. `python3 tools/forwardlint.py compiler/compiler.pas` is clean.
