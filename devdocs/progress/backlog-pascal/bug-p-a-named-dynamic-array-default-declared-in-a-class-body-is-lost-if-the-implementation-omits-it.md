---
slug: bug-p-a-named-dynamic-array-default-declared-in-a-class-body-is-lost-if-the-implementation-omits-it
track: P
type: bug
prio: 35
status: backlog
created: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
title: "A class method's `= nil` default on a named dynamic-array parameter is dropped when only the declaration carries it"
summary: "MEASURED 2026-09-06 at d754eeef1 against fpc 3.2.2 -Mobjfpc. `TC = class procedure M(const a: TArr = nil); end;` with `TArr = array of Integer`, implemented as `procedure TC.M(const a: TArr);` -- the default written on the DECLARATION only, which is the ordinary Pascal spelling -- makes `o.M` fail with `wrong number of parameters in call to TC.M`; fpc prints `M len=0`. The same omission is HONOURED for an Integer default and for an AnsiString default on methods of the same class, and the same TArr default written on BOTH sides works, so it is neither 'class methods lose their declaration defaults' nor 'nil defaults are lost' -- it is this type at this site. A LOUD refusal, not a wrong value, which is why it is ranked below the two interface crashes found beside it. Plausible-but-unmeasured: the declaration row records the ELEMENT kind for a named dynamic array (ParseTypeKind collapses TArr) while the implementation row records the array, so the two rows disagree about the parameter and the binding drops the default with it. I did not verify that."
---

# A declaration-only `= nil` default on a dynamic-array parameter is lost

```pascal
type
  TArr = array of Integer;
  TC = class
    procedure M(const a: TArr = nil);   { default HERE only }
  end;
procedure TC.M(const a: TArr);          { implementation does not repeat it }
begin WriteLn('M len=', Length(a)); end;
...
o.M;
```

| row | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `o.M` (default on the declaration only) | `error: wrong number of parameters in call to TC.M` | `M len=0` |
| `n: Integer = 5`, declaration only, same class | works | works |
| `const s: AnsiString = 'hi'`, declaration only | works | works |
| `const a: TArr = nil` written on **both** sides | works | works |
| the same shape as a **free routine** | works | works |

Four controls, and each removes a different explanation: it is not class
methods, not `nil`, not the declaration-only spelling, and not the type on its
own.

## Done when

Row 1 prints `M len=0`, with the four controls kept beside it in one file — the
value is plausible in every row, so only the rows' disagreement carries the
finding.

Found while closing
[[bug-p-a-default-value-is-accepted-on-an-open-array-parameter]], whose positive
control writes the default on both sides for exactly this reason and says so.
