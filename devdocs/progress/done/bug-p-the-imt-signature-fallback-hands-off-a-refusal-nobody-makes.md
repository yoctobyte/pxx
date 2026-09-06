---
slug: bug-p-the-imt-signature-fallback-hands-off-a-refusal-nobody-makes
track: P
prio: 40
type: bug
status: done
owner: ""
created: 2026-09-06
found-by: frankS
blocked-by: []
title: "A class 'implementing' an interface method at the wrong ARITY compiles, because the signature fallback defers to a diagnostic that is never made"
summary: "`IFoo = interface function M(a: LongInt): LongInt; end;` implemented by a class whose `M` takes NO argument compiles clean, and `f.M(1)` through the interface calls the 0-argument body. fpc refuses it: `No matching implementation for interface method \"M(LongInt):LongInt;\" found`. The cause is a HANDOFF BETWEEN TWO CORRECT-LOOKING PIECES, not a missing check in either. FindUMethForSig falls back to the first NAME match when no signature matches — deliberately, and its comment justifies the fallback by saying `does not implement` stays \"the IMT builder's diagnostic rather than this function's\". The IMT builder does make that diagnostic, but only when NO method of the name exists at all, so the arity case is refused by nobody. Each half is defensible alone and the pair has a hole. NOT introduced by the method-resolution-clause work that found it: measured with a clause AND with a plain same-named method, both compile, so the clause inherits the looseness rather than adding it."
---

# Measured 2026-09-06, compiler `66e848666e3c`

```pascal
IFoo = interface function M(a: LongInt): LongInt; end;
TFoo = class(TInterfacedObject, IFoo)
  function M: LongInt;        { no parameter — fpc: "No matching implementation" }
end;
var f: IFoo;  f := TFoo.Create;  writeln(f.M(1));
```

pxx compiles it and prints `7` — the 0-argument body reached through a 1-argument
slot. The extra argument is simply left in place; on this target it happens not
to disturb anything, which is what makes it silent rather than a crash. The
sibling defect `bug-p-a-write-call-inside-a-method-named-write-binds-to-the-member-whatever-its-arity`
records the other end of the same hazard: i386, arm32 and aarch64 *do* refuse a
call-argument-count mismatch, x86-64 has no such guard. So the same source is
plausibly a hard error on three targets and a wrong answer on the one everybody
measures on.

## Why it survived

`FindUMethForSig`'s fallback is not an oversight — it is argued for, so that "a
class whose implementation differs only cosmetically binds exactly as it did
before". The argument is fine; what fails is the *referral*. It says the refusal
belongs to the IMT builder, and the IMT builder's only refusal is

```pascal
if mmi < 0 then Error('class does not implement interface method: ' + imName);
```

which cannot fire, because the fallback guarantees `mmi >= 0` whenever any
method of the name exists. **The check is unreachable exactly when it is
needed** — the fallback that defers to it is also what disarms it.

## Shape of a fix

Have `FindUMethForSig` report whether it matched a SIGNATURE or fell back to a
name, and let the IMT builder refuse the fallback case (that is the site the
existing comment already nominates). Do not add the check on the
method-resolution-clause path alone: a clause is sugar for the same binding, so
a check there would make `function IFoo.M = Impl;` stricter than the plain
same-named `M` it desugars to, which is a second inconsistency rather than a
fix.

Worth checking in the same pass whether the cosmetic-difference cases the
fallback was written for are still reachable once arity is required — the
comment's example is a differing *type* spelling, not a differing arity, and
requiring equal arity may cost nothing it was protecting.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 0cdd83c71.
