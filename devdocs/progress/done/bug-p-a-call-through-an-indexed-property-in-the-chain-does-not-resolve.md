---
slug: bug-p-a-call-through-an-indexed-property-in-the-chain-does-not-resolve
title: "Calling a method pointer reached through an INDEXED PROPERTY does not resolve"
track: P
prio: 60
type: bug
status: done
owner: ""
blocked-by: []
summary: "RE-MEASURED 2026-09-06 at 22d8395be, compiler e54f10adf969: THE BOUNDARY IN THIS TICKET WAS WRONG AND THE DEFECT IS BIGGER. It is NOT the indexed property -- `TR(o).R.Fn(1)`, a cast base with no property anywhere in it, fails identically, and `o.GetI(0).Fn(1)` (an ordinary method call mid-chain) SUCCEEDS. The failing ingredient is WHICH WALKER PARSED THE CHAIN: ParseClassRecordSelectors, the shared selector walker every non-trivial spelling delegates to, builds no AN_CALL_IND at any point -- all five construction sites are in ParseLValueAST, which is why only the shapes ParseLValueAST handles by hand can call through a designator. AND THE THIRD POSITION IS THE ONE THAT MATTERS: `if <chain>(x) then` and `<chain>(x);` are REFUSED (loud, harmless), but `b := <chain>(x)` COMPILES AND IS SILENTLY WRONG -- the call never happens, the argument list is discarded, and the method pointer\'s own truthiness is assigned, so it answers TRUE for every argument. Proven with a body that can only return False: pxx still prints TRUE for `o.Items[0].Fn` and `TR(o).R.Fn`, fpc prints FALSE, and the other five shapes agree. A PROBE WITH A POSITIVE ARGUMENT CANNOT SEE THIS: `Fn(5)` is correctly TRUE and wrongly TRUE, so the expected value collides with the failure value and every row passes. Re-ranked 45 -> 60 to match its p60 sibling bug-p-an-open-array-literal-loses-its-length-through-a-procedural-type-call, which was ranked there for exactly this shape. The statement-position diagnostic also blames the base identifier `o` for a callee four selectors away."
---

# Calling a method pointer reached through an indexed property

- **Type:** bug (Pascal frontend — call resolution through a designator chain)
- **Track:** P
- **Found:** 2026-09-06, re-running [[feature-embed-pascal-script]] after
  [[bug-p-at-over-a-class-base-consumes-only-one-selector]] landed

## The boundary

`-Mdelphi`, at `67b07bc9e` / compiler `3bc524a975bd`:

| shape | pxx | fpc |
| --- | --- | --- |
| `o.Ev(1)` — field, one dot | compiles | compiles |
| `o.R.Ev(1)` — through a **record** field | compiles | compiles |
| **`o.Items[0].Fn(1)` — through an indexed property** | **refused** | compiles, prints `yes` |

```pascal
type TFn = function(x: Integer): Boolean of object;
     TInner = record Fn: TFn; end;
     TR = class private FI: TInner; function GetI(i: Longint): TInner;
          public property Items[i: Longint]: TInner read GetI; default;
          function F(x: Integer): Boolean; end;
...
if not o.Items[0].Fn(1) then writeln('no') else writeln('yes');
```

## Two diagnostics, one cause, and neither names the subject

| context | reported |
| --- | --- |
| statement — `o.Items[0].Ev(1);` | `o is not a procedure or function, so it cannot be called` |
| expression — `if not o.Items[0].Fn(1) then` | `expected 'then' before '('` |

The first is the actively misleading one: **it blames `o`**, the base identifier,
for a callee four selectors further along. Anyone reading it will go looking for
a `procedure o`.

## Why this is filed as a sibling and not as a reopen

`bug-p-at-over-a-class-base-consumes-only-one-selector` is correctly `done` —
its own four rows pass, verified by running them against this binary rather than
by reading the folder. It fixed **taking the address**. Taking the address and
**calling** are the same construct read two ways, and only one arm moved.

`devdocs/dev/normalise-dont-special-case.md` says it exactly: *"Fixed one arm of
a double case? Grep for the sibling before closing."* The evidence here is
unusually cheap to state — **the corpus wall moved two lines**, 5031 to 5033,
from `@Func.Attributes.Items[i].AType.OnApplyAttributeToProc` to the statement
that calls that same field.

## Done when

The three rows above compile, `o.Ev(1)` and `o.R.Ev(1)` still work, the
statement-position diagnostic names the callee rather than the base, and
uPSCompiler gets past 5033.


## 2026-09-06 — RE-MEASURED: the boundary above is wrong, and the third position is a silent wrong answer

Tree `22d8395be`, compiler `e54f10adf969`, fpc 3.2.2 `-Mdelphi`. Group 21
(the procedural value) took this ticket and re-measured before reading, which
is the only reason the two corrections below exist.

### 1. It is not the indexed property

Every row is the same callee `Fn: TFn` (`function(x: Integer): Boolean of
object`) reached through a different chain, in `if <row> then` position:

| row | chain | pxx | fpc |
| --- | --- | --- | --- |
| A | `o.Ev(1)` — field, one dot | OK | OK |
| B | `o.R.Fn(1)` — record field | OK | OK |
| D | `o.R2.R.Fn(1)` — record in record, three deep | OK | OK |
| G | `o.GetI(0).Fn(1)` — **an ordinary method call mid-chain** | **OK** | OK |
| C | `o.Items[0].Fn(1)` — indexed property | refused | OK |
| **I** | **`TR(o).R.Fn(1)` — a CAST base, no property at all** | **refused** | OK |
| J | `TR(o).Items[0].Fn(1)` | refused | OK |
| N | `(o.Items[0]).Fn(1)` | refused | OK |

**Row I is the correction.** The original boundary — *"the failing ingredient is
the INDEXED PROPERTY in the chain and NOT the chain depth"* — is disproven by a
row with no property in it, and row G disproves the natural repair ("a call node
in the chain"), because an explicit getter call mid-chain works.

**The actual ingredient is which walker parsed the chain.** A cast base and a
property step both delegate to `ParseClassRecordSelectors`
(`pasparser_lval.inc:4849`), and that routine **builds no `AN_CALL_IND` at any
point in its 700 lines.** All five construction sites are in `ParseLValueAST`,
which is why exactly the spellings `ParseLValueAST` handles by hand can call
through a designator. Its selector loop is `while CurTok.Kind in [tkDot,
tkLBrack]`, so a `(` ends the walk and is left in the stream for whatever comes
next to complain about — which is why the error text names the *following*
token and never the defect.

### 2. The position that compiles is the one that is wrong

| position | pxx |
| --- | --- |
| `if <chain>(x) then` | refused: `expected 'then' before '('` |
| `<chain>(x);` | refused: `o is not a procedure or function` |
| **`b := <chain>(x)`** | **compiles, and answers TRUE for every argument** |

`Fn` returns `x > 0`. With `x = -5`, seven shapes measured:

```
pxx:  FALSE Ev-field  FALSE R.Fn  FALSE R2.R.Fn  FALSE GetI().Fn   TRUE Items[].Fn   TRUE TR().R.Fn  FALSE via-var
fpc:  FALSE Ev-field  FALSE R.Fn  FALSE R2.R.Fn  FALSE GetI().Fn  FALSE Items[].Fn  FALSE TR().R.Fn  FALSE via-var
```

**The call never happens.** Re-run with a body that can only return `False`, and
the same two rows still print `TRUE` — so the argument list is discarded and
what gets assigned is the truthiness of the method pointer itself, which is
non-nil. Not a wrong argument: no call.

**A probe with a positive argument cannot see this.** `Fn(5)` is correctly TRUE
and wrongly TRUE — the expected value collides with the failure value, every row
passes, and the silent arm ships. It took an argument whose correct answer is
`FALSE` to separate them. Second instance of that rule in one day; the first is
`6ccba196e` (*"the expected value must differ from what the BUG EMITS"*).

### 3. What this changes

Re-ranked **45 -> 60**, to match its sibling
`bug-p-an-open-array-literal-loses-its-length-through-a-procedural-type-call`,
which was ranked 60 for this exact shape and is now `done` at `fe0c492d1`.
**Both members of this group turned out to have a loud refusal in front of a
silent wrong answer, and in both the refusal is what got written down.**

### Done when

The rows above compile AND row-by-row match fpc at runtime with a negative
argument, `o.Ev(1)` / `o.R.Fn(1)` / `o.GetI(0).Fn(1)` still work, the
statement-position diagnostic names the callee rather than the base, and
uPSCompiler gets past 5033. **A test asserting only that the refused rows now
compile would pass over the silent arm** — the assertion has to be the returned
value, with an argument whose right answer is not the failure value.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6453a7ad0.
