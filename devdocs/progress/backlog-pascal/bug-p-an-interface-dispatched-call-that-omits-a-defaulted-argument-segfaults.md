---
slug: bug-p-an-interface-dispatched-call-that-omits-a-defaulted-argument-segfaults
track: P
type: bug
prio: 55
status: backlog
created: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
title: "A call through an interface reference that omits a defaulted argument compiles clean and segfaults"
summary: "MEASURED 2026-09-06 at d754eeef1 against fpc 3.2.2 -Mobjfpc. `IFoo.N(n: Integer = 7)` implemented by a TInterfacedObject descendant: `i.N` through the interface reference compiles clean and SEGFAULTS; `i.N(3)` on the same reference, same object, same binary prints 3. fpc prints 7 for the omitted form. Both a Double and an Integer default crash, so it is not the value's width. The control is the point: the ONLY difference between the crashing and working rows is whether the argument was written, so this is the default FILL on an interface-dispatched call and not interface dispatch, not the default's shape, and not the object. Class dispatch on the identical method is correct. Found while closing bug-p-a-default-value-is-accepted-on-an-open-array-parameter; the lane may be A rather than P if the cause is in the IMT thunk, and I did not locate it."
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

Sibling found in the same sitting, different input, same subsystem:
[[bug-p-an-interface-dispatched-call-passing-a-named-dynamic-array-segfaults]].
No shared cause established.
