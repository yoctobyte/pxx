---
summary: "Pascal: `lst[j]^.Field` on a TPropList resolves only the FIRST field — every other one is 'no such member'; via a local variable it works"
type: bug
track: A
prio: 55
---

# `arr[i]^.Field` loses the pointed-to record type — but only in some units

- **Type:** bug (compiler — record/field resolution — **Track A**)
- **Opened:** 2026-07-31 by Track B, running the GUI suite for
  [[feature-pcl-seam-seal]]. **Pre-existing**, not caused by that work: the same
  compile fails identically on a stashed tree.

## Symptom

Eight lines, against the shipped RTL:

```pascal
program p;
uses typinfo;
var lst: TPropList; j: Integer;
begin
  j := 0;
  if lst[j]^.Kind = 5 then WriteLn('x');
end.
```

```
pascal26:6: error: "Kind": no such member on this record/class
```

`TPropList` is `array[0..511] of PPropInfo` and `TPropInfo` plainly has a `Kind`
field — `var r: TPropInfo; r.Kind := 1;` compiles.

## What is and is not affected

| form | result |
| --- | --- |
| `lst[j]^.NamePtr` — the FIRST field of the record | **ok** |
| `lst[j]^.Kind`, `.TypeRef`, `.GetKind`, `.OrdType` — any later field | **error** |
| `p := lst[j]; p^.Kind` — the same deref via a local | **ok** |
| `var r: TPropInfo; r.Kind` | **ok** |

Only offset 0 resolves, which reads as: the element type is lost and the
expression falls back to a bare pointer dereference.

## What was ruled out (measured, not reasoned)

- **Not the shape of the types.** A synthetic unit declaring the same
  `record` / `^record` / `array[0..511] of ^record` chain, with the same leading
  `PString` field, compiles the identical expression fine.
- **Not the unit boundary.** The synthetic version above is in a unit too.
- **Not unit size / symbol-table growth.** `typinfo`'s INTERFACE alone (its real
  declarations, empty implementation) compiles the expression fine, and stays
  fine with 400 dummy functions appended.
- **Not the `var kind: Int64` parameter of `GetFieldPtr`.** Pascal is
  case-insensitive so that identifier was the obvious suspect; renaming it
  throughout does not fix it.
- **Not `GetFieldPtr := @PUInt8(instance)[fi^.Offset];`** — a cast-index-deref
  chain, the other obvious suspect. Replacing it does not fix it.

So it needs something in `lib/rtl/typinfo.pas`'s IMPLEMENTATION, and that
something has not been isolated. A cut-the-file-and-append-`end.` bisect points
at the region ending with `GetFieldPtr`, but that evidence is weak — every cut
also removes declarations, so the boundary may only mark the first syntactically
valid cut rather than the guilty construct. Stated as unknown rather than
guessed.

## Why it matters

It blocks the **eliah IDE** build, which is the one red in `tools/gui_suite.sh`:

```
FAIL  eliah_ide -- compile:   near: plist  j    >>> Kind
```

`apps/ide/eliah/main.pas:784` is `plist[j]^.Kind`, i.e. exactly this. Worse, the
suite then runs the STALE binary from a previous build and reports
`OK eliah_ide (real window 1100x727)` two lines later — so the failure looks
half-green. That reporting gap is worth fixing on the Track T side regardless of
this bug.

The failure is at least LOUD. But "only the first field of a record is
reachable" is one typo away from being silent: a record whose first field
happens to have the same type as the one you meant would compile and read the
wrong bytes.

## Gate

`make test` + self-host byte-identical, plus a regression compiling the eight
lines above, and `tools/gui_suite.sh` reaching a green `eliah_ide -- compile`.
