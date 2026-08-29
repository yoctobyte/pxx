---
slug: bug-b-rtti-read-of-a-getter-method-property-answers-zero
track: B
prio: 60
type: bug
status: done
owner: frankB
blocked-by: []
summary: "GetOrdProp/GetStrProp handle only GetKind=0 (a direct field) and silently return 0 / '' for GetKind=1 (a read METHOD), so `property Num: Integer read GetI` reads as 0 through RTTI while the same property reads 107 directly. The WRITE half already dispatches through setter methods — one arm of a double case was implemented. Also: SetOrdProp casts every setter argument to Integer, truncating an Int64 property."
---

# RTTI read of a getter-method property answers 0

- **Track B** (`lib/rtl/typinfo.pas`). Found 2026-08-28 by frankB while working
  [[feature-typinfo-facade-unit]] — the facade's whole purpose is reading
  properties, so it cannot be built on top of this.
- Measured against pin **v389** (`325b4479070a`).

## Repro

```pascal
uses typinfo;
type
  TThing = class(TObject)
  private
    FI: Integer; FS: string;
    function GetI: Integer;
    function GetS: string;
  published
    property ByField: Integer read FI write FI;
    property ByMethod: Integer read GetI write FI;
    property StrByMethod: string read GetS write FS;
  end;
function TThing.GetI: Integer; begin GetI := FI + 100; end;
function TThing.GetS: string; begin GetS := 'via-' + FS; end;
```

with `t.FI = 7`, `t.FS = 'x'`:

| property | read directly | read through RTTI |
| --- | --- | --- |
| `ByField` | 7 | 7 |
| `ByMethod` | 107 | **0** |
| `StrByMethod` | `via-x` | **''** |

No error, no diagnostic — a plausible zero.

## Cause

`GetOrdProp` and `GetStrProp` are written as

```pascal
if p^.GetKind = 0 then
begin
  ... read the field at p^.GetRef ...
end;
{ no else }
```

`GetKind = 1` means `GetRef` is the getter method's code pointer, and the
compiler *does* emit it — verified: `property Dbl: Double read GetD write SetD`
emits `GetKind=1 SetKind=1`, and even `read GetI write FI` emits `GetKind=1
SetKind=0`. The function falls off the end with its result still at the
initialising `:= 0`.

**One arm of a double case.** `SetOrdProp` and `SetStrProp` in the same file
already handle `SetKind = 1` by calling through a `TOrdSetter` / `TStrSetter`
procedural type — the write direction was finished and the read direction was
not. `devdocs/dev/normalise-dont-special-case.md`: the second path is the one
that stays broken.

## Second defect in the same lines

`SetOrdProp` declares its setter trampoline as

```pascal
TOrdSetter = procedure(Self: Pointer; v: Integer);
```

and calls `setter(instance, Integer(v))` for **every** width. An `Int64`
property with a setter method therefore has its value truncated to 32 bits on
the way in. Same shape of defect (the width is known from `p^.OrdType` and is
being ignored), so it is fixed here rather than filed separately.

## Fix

Dispatch the read side through width-correct procedural types, mirroring what
the write side does, and give the write side the same width discrimination.
A getter's return width must be declared exactly — reading an `Integer`-returning
getter through an `Int64`-typed trampoline reads whatever the ABI left in the
high half of the return register.

## Gate

Track B's: `make lib-test`, plus a `test/lib_typinfo_props.pas` asserting every
property shape (field/method read, field/method write) round-trips through the
accessors and agrees with the direct property read.

## Resolution (2026-08-28, frankB)

Fixed in `lib/rtl/typinfo.pas` alongside [[feature-typinfo-facade-unit]], which
is what surfaced it — the facade reads properties, so it could not be built on
accessors that answered 0.

The single `TOrdSetter = procedure(Self: Pointer; v: Integer)` was replaced by a
trampoline **per width** (`TOrdGetter8s`/`8u`/`16s`/`16u`/`32s`/`32u`/`64`, the
matching setters, plus string, Single, Double and object shapes), because a
procedural type is how the ABI is told what to read and write: an
Integer-returning getter called through an Int64-shaped one reads whatever the
callee left in the high half of the return register. `GetOrdProp` and
`GetStrProp` grew the `GetKind = 1` branch they never had; `SetOrdProp` stopped
casting every setter argument to `Integer`.

Both defects were one shape — a width or a dispatch decision available in
`p^.OrdType` and ignored.

Verified against `$(PXX_STABLE)` v389 (`325b4479070a`): the ticket's own repro
now answers 107 and `via-x` where it answered 0 and `''`.

Regression: `test/lib_typinfo_props.pas`, wired into `make lib-test`. Every
property kind appears TWICE, once `read FField` and once `read GetIt`, and each
getter perturbs the value (+100, `'via-'`, doubling) so a silently-skipped method
call reads as the raw field rather than as the right answer by luck. The
`m_int64_setter_not_truncated` row is the second defect's.

Gate: `make lib-test` green, `make demos` 35/35 (typinfo is under all of
`lib/pcl`), both against v389.

## Log
- 2026-08-28 — resolved, commit cfa72767f.
