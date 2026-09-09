---
track: P
prio: 50
type: bug
blocked-by: []
status: done
owner: ""
summary: "FIXED 2026-09-09. `Take(HashIt)` inside a sibling method now REFERENCES the method — prints `took 42`, matching fpc 3.2.2 -Mdelphi byte for byte. The cause was NOT the lowering: ir.inc:5659 and IRMethodRefToTemp were correct and never ran, proved by PXXDBG=a.ast (the argument reached IR as AN_CALL/tyInt32, and the route tests AN_METHODREF/tyRecord). The bare-Self method-call loop in pasparser_stmt.inc asked TryParseBracketArgForSlot and not TryDelphiBareProcArg, so the reference reading was never offered; the free-proc loops ask both side by side. It presented as a lowering bug because the overload PROBES do reach TryDelphiBareProcArg and built a correct methodref twice — the match came from one reading and the tree from another. Two changes: a method arm in TryDelphiBareProcArg (FindProc sees free routines only) and the missing door in that loop. Test covers the virtual case (binds the override, 241 not 141 — previously unexercised) and both precedence directions (bare paramless and bare all-defaulted still CALL, which is where the Params[0]-is-Self off-by-one would silently pass an address). Gate GREEN."
---

# A bare method name in argument position is called instead of referenced

## Repro — 14 lines, no generics

```pascal
program p; {$mode delphi}
type
  TOnHash = function(const v: LongInt): LongInt of object;
  TC = class
    function HashIt(const v: LongInt): LongInt;
    procedure Take(const h: TOnHash);
    procedure Go;
  end;
function TC.HashIt(const v: LongInt): LongInt; begin Result := v + 1; end;
procedure TC.Take(const h: TOnHash); begin WriteLn('took ', h(41)); end;
procedure TC.Go; begin Take(HashIt); end;      { <-- here }
var c: TC;
begin c := TC.Create; c.Go; end.
```

fpc 3.2.2 `-Mdelphi`: `took 42`. pxx: `no overload of Take matches these
arguments / argument types: (LongInt)`.

**The dialect is load-bearing.** In `objfpc` a bare method name IS a call and
`@` is required — fpc rejects the same program there, with a different message.
A probe written in objfpc mode says nothing about this bug; the corpus unit is
`{$MODE DELPHI}`.

## The matrix — which contexts already work

| context | pxx | fpc |
| --- | --- | --- |
| `F := HashIt` (assignment) | ok | ok |
| `Result := HashIt` (return) | ok | ok |
| `Take(HashIt)` (argument) | **refused** — `no overload of Take matches` | ok |
| `Take(Self.HashIt)` (qualified argument) | **refused** — `wrong number of parameters` | ok |

Two diagnostics, one missing reading — which is why it can read as two bugs.

## Mechanism

`TryParseParenlessMethodRef` (pasparser_call.inc) is the ONE place an
`AN_METHODREF` is built for this family, and its own comment says to count
construction sites rather than add to them. It has callers for a method-pointer
CAST and for the assignment site. **Argument position has a different door,
`TryDelphiBareProcArg` (pasparser_lval.inc), and that door asks `FindProc` —
which does not see a method.** So a bare method name in an argument list never
reaches the reference reading at all and falls to `ParseArgExpr`, which reads a
call. A rule spelled per CALLER, failing by an absent copy.

## What was tried, measured, and REVERTED

Routing the method case into the one helper from `TryDelphiBareProcArg`:

- **Fixes the free-callee half.** A bare method name given to a FREE procedure
  went refused -> correct (`freetake 42`, matching fpc).
- **Breaks the method-callee half into a SEGFAULT.** `Take(HashIt)` where `Take`
  is a method compiled and died calling through the pair. `PXXDBG=a.ast` shows
  the argument is still `kind=8` (AN_CALL), never `AN_METHODREF` (45), yet typed
  `tk=11` (record) — so it slips past overload matching and is marshalled as a
  method pointer it is not. **There is a third site deciding this that I did not
  locate**, and until it is found this fix must not land: today's refusal is
  honest and a segfault is not.

Two facts any future attempt needs, both measured:

- **`Params[0]` of a method is the implicit `Self`** (`pn[0] := 'Self'`), so the
  free-routine precedence tests — paramless function, all-defaulted — must read
  slot 1 and compare `ParamCount = 1`, not 0. Reading slot 0 asks whether SELF
  has a default; both mis-aimings are silently false and both err toward
  addressing what Delphi calls. `MethodResultSatisfiesTarget` already makes this
  adjustment in its `ParamCount > 1` test.
- **The overload probe in `FindUMethOverloadAhead` (pasparser_call.inc) parses
  arguments with a bare `ParseArgExpr` and no hook**, then rewinds. When the
  probe and the real parse disagree about call-vs-reference, the probe wins the
  SELECTION and the real parse builds the node. That is a real gap and worth
  closing on its own, but it is NOT this bug's cause: the probe only runs with
  more than one candidate, and the repro has a single `Take`.

## Why the precedence cannot simply be the assignment site's

The assignment site knows its DESTINATION and can ask
`MethodResultSatisfiesTarget` — would calling this already produce the method
pointer the target wants? In argument position the destination is not known yet,
because overload resolution has not run. The question available there is the
free-routine one: can this be called parenless at all? A paramless function can,
and Delphi calls it; a routine that REQUIRES arguments cannot, so the reference
is the only reading that compiles.

# 2026-09-09 — the parse half is SOLVED and it is not enough (frankuser)

Attempted, measured, **not landed**. `TryDelphiBareProcArg` in
`compiler/pasparser_lval.inc` asks `FindProc`, which sees free routines only,
so inside a method body the reference reading was never reached at all. Adding a
method arm — mirroring `TryParseParenlessMethodRef`'s implicit-Self arm in
`pasparser_call.inc` verbatim, `ASTRight := UMthVirSlot` included — makes the
repro COMPILE. It then **segfaults at the indirect call**:

```
ok: bare  [code=69400B data=3504B bss=43532B procs=140]
took            <- prints the literal, dies calling h(41)
Segmentation fault (core dumped)
```

So the ticket's own warning holds and this is the same wall the earlier attempt
hit: **the parser is now right and something downstream is not.** What that
changes is the search area — it is no longer 'find the third site that decides
the reading'. The reading is decided correctly; the defect is in lowering the
`AN_METHODREF` argument to a method-pointer temp, or in the temp's layout at the
call. `ir.inc:5659` already routes `AN_METHODREF` to `IRMethodRefToTemp` when the
param is `tyRecord`, so the route exists and the value it produces is wrong —
check the `Self` operand actually reaches the temp, and check the two-word
method-pointer layout against what the `of object` call site reads.

**Do not land the parser arm alone.** Today's `no overload of Take matches` is an
honest refusal; a segfault is not, and the arm converts one into the other.

Three measured facts worth keeping, all cheap to get wrong:

- `Params[0]` of a method is the implicit `Self`, so the free-routine precedence
  tests must read slot 1 and compare `ParamCount = 1`. Reading slot 0 asks
  whether `Self` has a default — always false, and false in the direction that
  silently takes an address where Delphi would have called.
- `ASTRight := UMthVirSlot[rmmi]` is load-bearing. Omit it and a **virtual**
  method binds the base rather than the override — a silently wrong target that
  no repro in this ticket exercises.
- `FindUMethOverloadAhead` probes arguments with a bare `ParseArgExpr` and no
  hook. That is a real second gap, and it is NOT this bug's cause: the repro has
  a single `Take`.

The working arm is reproducible from this description in about ten minutes; it
was deliberately not committed, because a patch that turns a diagnostic into a
crash is worse to inherit than a description of one.

## Resolved 2026-09-09 by frankH — the loop never offered the door; the lowering was never wrong

`took 42`, matching fpc 3.2.2 `-Mdelphi` byte for byte. Two changes, and
neither is in `ir.inc`.

### The diagnosis above pointed one layer too deep, and the AST says so

The handoff's reading was that `ir.inc:5659` routes `AN_METHODREF` to
`IRMethodRefToTemp` "and the value it produces is wrong". **That route never
ran.** With the parser arm in place and the repro compiling, `PXXDBG=a.ast:*`
gives the argument as

    #8202 kind=8 tk=11 ival=137     { AN_CALL of TC.HashIt, tyInt32 }
      #8200 kind=9
        #8201 kind=3 tk=6 ival=105  { AN_IDENT Self }

`kind=8` is `AN_CALL` and `tk=11` is `tyInt32` — not `AN_METHODREF`/`tyRecord`.
`ir.inc:5659` tests exactly those two things, so it could not fire, and the IR
confirms it: `IRMethodRefCode` emits `IR_PROCADDR` (non-virtual) or
`load_mem`/`binop`/`load_mem` (virtual) and **neither emits a call**, while
`TC.Go` contained `call a=137` with `Self` as its only argument, its LongInt
result stored into the 16-byte temp and then invoked as a code address.
`IRMethodRefToTemp` and its route were correct throughout.

### The actual defect: one arm of a double door

`pasparser_stmt.inc`'s bare-`Self` method-call loop asked
`TryParseBracketArgForSlot` and **not** `TryDelphiBareProcArg`. The free-proc
loops at `pasparser_stmt.inc:8550` and `pasparser_expr.inc:8525` ask both, side
by side. So the reference reading was never offered here at all and `ParseExpr`
took the bare name under call-first precedence.

That loop's own comment already records this shape, about the OTHER door:
*"Every other call path asks; this one — the bare `Log(...)` inside a sibling
method, implicit Self — hand-rolled its loop and asked nothing."* The fix for
that added one of the two doors the other paths ask at. This is
`normalise-dont-special-case.md`'s *"fixed one arm of a double case? Grep for
the sibling before closing"*, with the sibling in the same five lines.

### Why it presented as a lowering bug, which is the transferable part

`TryDelphiBareProcArg` **is** reached — from the overload probes, which parse
the argument speculatively. Instrumented, the new method arm fires **twice**,
building a correct `AN_METHODREF` each time, and both are discarded with the
probe. Those firings are what made `Take` match. This loop then re-parsed the
argument as a call.

**So the verdict came from one reading and the tree from another.** That is
precisely why the symptom looked downstream: the overload match had already
succeeded on a methodref, so the argument "was" a methodref by the time anyone
asked, and the only wrong thing left to suspect was the lowering. The
discriminator was dumping the AST rather than reasoning from the match.

### The two changes

1. `TryDelphiBareProcArg` (`pasparser_lval.inc`) gains a method arm for when
   `FindProc` finds nothing: resolve the implicit `Self` exactly as
   `TryParseParenlessMethodRef`'s no-receiver arm does and build its node.
2. That loop (`pasparser_stmt.inc`) asks the door.

Both of the handoff's warnings were load-bearing and are now under test rather
than under comment:

- **`ASTRight := UMthVirSlot` is exercised.** Row 2 of the new test references a
  **virtual** method through a derived instance and prints `241` (the override),
  not `141` (the base). Nothing exercised this before.
- **The `ParamCount` off-by-Self is real and the tests discriminate.** Rows 3
  and 4 pass a BARE paramless and a BARE all-defaulted function, which must
  still CALL: they print `5` and `70`. Reading `Params[0]` would ask whether
  `Self` has a default — always false — and silently pass an address into a
  `LongInt` sink, so those rows print a garbage number under the wrong slot
  rather than failing to compile.

`FindUMethOverloadAhead`'s hookless `ParseArgExpr` probe is still a real second
gap and is still not this bug's cause, exactly as the handoff said. It is why
the arm fires twice; it is not why the tree was wrong.

Gate GREEN (20 PASS). `test_delphi_bare_method_name_in_argument_position` is
wired beside the chained-receiver test; `.expected` is fpc's own output.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit ad7c03b03.
