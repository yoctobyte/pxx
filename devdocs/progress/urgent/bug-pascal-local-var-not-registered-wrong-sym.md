---
prio: 70
---

# A method's LOCAL is not registered, and the name resolves to an unrelated symbol

- **Type:** bug (scoping / name resolution) — **potentially silent wrong behaviour in any program**
- **Track:** P — Pascal frontend (shared parser: also A's ground)
- **Status:** urgent — opened 2026-07-13. **Evidence gathered, cause not yet isolated.**
- **Found in:** fcl-json's own suite (`testjsondata.pp`), while walking
  [[feature-pascal-corpus-fpjson]]. NOT specific to it — the mechanism is general.

## What is observed
In `TTestString.TestFormat`:

```pascal
procedure TTestString.TestFormat;
Var
  S : TJSONString;          { a CLASS }
begin
  S := TJSONString.Create('aloha');
  try
    AssertEquals('FormatJSON equals JSON', S.AsJSON, S.FormatJSOn);   { <-- fails }
```

The parse dies with `Expected: ,` at the `.` of `S.AsJSON` — because **`S` does not resolve to
the local**. Instrumented at the ident-resolution site:

```
DBG S line=1714 idx=172 tk=23 rec=0 kind=2      { tk 23 = tyAnsiString, kind 2 = skParam }
DBG S line=1719 idx=172 tk=23 rec=0 kind=2
```

`S` resolves to an **skParam of type AnsiString at symbol index 172** — a low index, i.e. a
PARAMETER belonging to some *other* routine — not to the method's own `S : TJSONString`. So the
member access `.AsJSON` is attempted on a string, finds nothing, and the argument list then
demands its comma.

The same happens in `TestClone` (also `S : TJSONString`), so it is not one method.

## The second, probably decisive, observation
Instrumenting `ParseVarSection` shows a var section parsed with **`CurProc = -1`** — no
enclosing routine, i.e. **GLOBAL scope** — for a var block that belongs to a method:

```
DBG varsec line=1702 tok=var curproc=-1        <-- a method's locals, at global scope
DBG varsec line=1686 tok=var curproc=61
DBG varsec line=1685 tok=var curproc=184
```

So at least one routine's `var` block is being parsed outside its routine context. That would
register its locals as globals and leave the routine itself without them — which is exactly the
shape of the symptom.

## Why this is urgent rather than a corpus curiosity
This is name resolution silently binding an identifier to the WRONG SYMBOL. In this instance it
happened to produce a parse error (a member access on a string), which is lucky. The same
mis-binding between two symbols of *compatible* types would compile and run, reading and writing
the wrong variable. Nothing about the mechanism is specific to fcl-json.

## Confirmed decl-ORDER dependent
Moving `TestFormat`'s implementation to the END of the unit's implementation section makes the
error disappear (the compile then proceeds to the next, unrelated wall). So what is or is not
registered depends on where the body sits — the same family as
[[bug-pascal-decl-order-ret-recid]] (b291), where a method's return-type class id was recorded at
its BODY rather than its DECLARATION.

## Next step (do NOT guess — this resisted six standalone reproductions)
Every attempt to reproduce it in a small program PASSED, including one with the exact class
shapes, and one with a later method taking `S : String` as a parameter. It only fails inside the
real file. So:

1. Find which routine's `var` section gets `CurProc = -1`, by printing the routine name/index
   alongside. That is the thread to pull.
2. Then determine why its body is parsed without a routine context — the declaration pre-scan
   (`PreScanPass` / `PreScanSkipRoutineBody`) is the obvious suspect, since it is what walks
   bodies with different state.

Instrumentation, not reproductions. See [[project_dump_tokens_before_theorising]].

## Gate
`make test` + self-host byte-identical.
