---
slug: bug-p-an-interface-dispatched-call-that-omits-a-defaulted-argument-segfaults
track: P
type: bug
prio: 55
status: done
created: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
title: "A call through an interface reference that omits a defaulted argument compiles clean and segfaults"
summary: "CLOSED PENDING-COMMIT. TWO ARMS, NOT ONE, AND THE SECOND WAS FOUND ONLY BECAUSE THE FIXTURE CARRIED ELEVEN RECEIVER SHAPES. `o.M;` with no parentheses on a method whose parameters all carry defaults: CheckMethodCallArity ACCEPTS the short call precisely BECAUSE the missing parameters have defaults, and then nothing supplied them -- the call node went out with no arguments and the callee read its parameter off the register. CanFillDefaultsFrom is the helper an author reaches for and it silently declines here: it asks `(CurTok.Kind = tkRParen) and <can default>`, i.e. TWO questions under one name, and with no parentheses at all CurTok is `;`. Split out as ParamsDefaultedFrom, which is the half a parenless call needs; the instance-method arm had found this in 2026-08 and spelled the test out by hand, so the next three arms would have copied the line rather than the reasoning. Fixed at four arms: the plain interface reference (ParseLValueAST), the parenthesised one (the selector walker), and the two grouped `(expr).M` arms in pasparser_expr.inc. THE SELECTOR-WALKER FIX HAD TO GO WHERE THE TOKEN IS READ, NOT IN THE `else`: that arm's paren test and its else are ~95 lines apart across a nested argument loop, a fill written in the else did not run, and four builds with tagged arms were what established it -- the aiming, not the reading, is what found it. Measured against fpc 3.2.2 across eleven receiver shapes -- free routine, instance, class method, metaclass, record method, selector chain, implicit Self, grouped, grouped cast, interface, grouped interface, plus the explicit-argument control. TEN OF THE ELEVEN WERE ALREADY CORRECT when this was filed, so a fixture holding one shape would have been green on any nine."
---

# An interface-dispatched call that omits a defaulted argument segfaults

```pascal
{$mode objfpc}{$H+}
type
  IFoo = interface
    ['{11111111-2222-3333-4444-555555555555}']
    procedure D(d: Double = 2.5);
    procedure N(n: Integer = 7);
  end;
  TFoo = class(TInterfacedObject, IFoo)
    procedure D(d: Double = 2.5);
    procedure N(n: Integer = 7);
  end;
...
var i: IFoo;
begin
  i := TFoo.Create;
  i.D;      { <- segfault }
  i.N;      { <- segfault }
end.
```

| row | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `i.D;` / `i.N;` (defaults omitted) | compiles, **segfault** | `D 2.50` / `N 7` |
| `i.D(1.5);` / `i.N(3);` (same file, args written) | `D 1.50` / `N 3` | same |
| `f.D; f.N;` on a `TFoo` variable (class dispatch) | correct | same |

**The middle row is why this is a finding and not a crash report.** Same file,
same interface reference, same object, same binary shape — the only thing that
differs is whether the argument was written at the call. So the default FILL on
an interface-dispatched call is the suspect, and interface dispatch itself,
the default's declared shape, and object lifetime are all controlled for.
Both a float and an ordinal default crash, so it is not the value's width.

## Not investigated

I did not locate the fill. A plausible-but-unmeasured reading is the Self
injection: an interface method's parameter row is shifted by one to make room
for Self, and the shift loop in `pasparser_decl.inc` copies `mPDefault`,
`mPDefaultVal`, `mPDefaultIsStr`, `mPDefaultIsSet`, `mPDefaultSOff` and
`mPDefaultSLen` but **not** `mPDefaultIsFloat`. That omission is real and
visible in the source; it does not explain the Integer row, so it is at most
half of this and possibly none of it. Do not take it as the diagnosis.

## Done when

`i.D;` and `i.N;` above print fpc's values, and a row exists asserting the
omitted and written spellings **in the same file** — two files each printing a
plausible number both pass; two numbers on adjacent lines of one output do not.

## The sibling, and what "no shared cause" does and does not mean

[[bug-p-an-interface-dispatched-call-passing-a-named-dynamic-array-segfaults]] was found in the same sitting, in the same subsystem, at the same
priority. **Read that pairing carefully, because the honest statement is weaker
than either "they are the same bug" or "they are independent."**

What was measured is that each crashes under its own trigger with the other's
trigger controlled out: this one with a scalar parameter and no array anywhere,
that one with no default value anywhere. Neither is a special case of the other's
repro.

What was NOT measured is whether one cause explains both. I did not locate
either. Two crashes in one dispatch mechanism have every reason to share a
cause, and a reader who fixes one should expect the other to fall out and check
rather than assume it will not — **the pair being listed here is not evidence
that they are two.** If they turn out to be one, close this and say so; that is
a better outcome than two tickets held apart by a sentence nobody measured.


## Closed 2026-09-06 (frankB) — two arms, and the fixture is the finding

`CheckMethodCallArity` exits quietly when parameter 1 carries a default, which is
correct: the call IS legal. Nothing then filled the arguments. **A guard whose
entire justification is "the missing parameters have defaults" and which does not
supply them is not a partial implementation — it is a guard that accepts a call
it has not made valid.**

The helper an author reaches for declines here, silently:

```pascal
function CanFillDefaultsFrom(mpi, nextIdx: Integer): Boolean;
begin
  Result := (CurTok.Kind = tkRParen) and ParamsDefaultedFrom(mpi, nextIdx);
end;
```

Two questions under one name — *the argument list ends here* AND *the rest can
default*. With no parentheses at all CurTok is `;`. Now split, and
`ParamsDefaultedFrom` is the half a parenless call needs. **The instance-method
arm had found this in August and written the test out by hand**, so the three
arms that still had the hole would have copied that line rather than found its
reasoning; naming it is what stops the fourth copy.

### The second arm, and how it was actually found

Fixing the plain interface reference left `(i).M;` still segfaulting. That arm is
in the selector walker, where the paren test and its `else` are **~95 lines apart
across a nested argument loop** — a fill written in the `else` did not run for
this shape, and reading the code did not show why. What settled it was **tagging
each candidate arm with a distinct `Warn` and one build**: the builder fired,
the else did not. The fill now sits immediately after the token is read:

```pascal
Next; { consume method name }
if (CurTok.Kind <> tkLParen) and ParamsDefaultedFrom(mpi, 1) then
  FillDefaultArgs(mpi, 1, callN, lastA);
if CurTok.Kind = tkLParen then
```

**Put the decision where the token is READ, not where the block happens to
close.** Four builds is what the alternative cost.

### Eleven shapes, and ten of them were already right

free routine · instance method · class method on the class name · class method
through a metaclass · record method · selector chain · implicit Self · grouped
`(o)` · grouped cast `(o as T)` · interface reference · grouped interface
reference — plus the explicit-argument control.

fpc 3.2.2 answers 7 for all of them. When this was filed, pxx answered 7 for ten
and crashed on one. **A fixture holding a single shape would have been green on
any nine of the eleven**, which is the argument for the file's shape: the shapes
are the assertion, not the arrangement.

The explicit-argument control is what made the crash diagnosable in the first
place — same reference, same object, same binary, differing only in whether the
argument was written.

### Also fixed, and honestly labelled

The CLASS-method Self-shift loop in `pasparser_decl.inc` copied five of the six
default channels and omitted `mPDefaultIsFloat`; the INTERFACE-method shift loop
in the same file copies all six. **I could not construct a program that reads
the wrong value** — the defaults that reach a call come from the implementation
row, so the declaration row's flag is not consulted on any path I could reach.
Fixed anyway: the loop's contract is *shift the row*, a sibling loop shows what
the row is, and an omission that is unreachable today is inherited by the next
path that reads it.

### The sibling

[[bug-p-an-interface-dispatched-call-passing-a-named-dynamic-array-segfaults]] is
**not** closed by this and was not caused by it — it has no default values
anywhere, and it still crashes at this commit. The two were filed as a pair with
the independence explicitly NOT established; this close does not settle that
question either way.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 3755856b7.
