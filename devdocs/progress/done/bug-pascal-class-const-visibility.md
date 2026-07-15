---
summary: "class CONSTS parse as UNSCOPED GLOBALS: same-named consts in two classes silently clobber (both read the last decl), and a class const clobbers a same-named GLOBAL const — silent wrong values in valid FPC code; visibility (tclass12b) is the minor residual"
type: bug
track: P
prio: 60
---

# class consts are unscoped globals — silent name-collision miscompiles

- **Type:** bug (SILENT wrong values on valid FPC code — not a conformance
  nicety). **Track P.**
- **History:** filed 2026-07-15 as the low-prio visibility residual split from
  [[bug-pascal-member-visibility-unenforced]]; UPGRADED same day after the user
  flagged the collision hazard and both shapes reproduced as silent-wrong
  (compat escape rule: silent wrong behavior = real bug ticket, not parity).

## Repro 1 — cross-class clobber

```pascal
type
  TA = class private const Max = 5;  public function GetMax: Integer; end;
  TB = class private const Max = 99; public function GetMax: Integer; end;
function TA.GetMax: Integer; begin Result := Max; end;
function TB.GetMax: Integer; begin Result := Max; end;
```
FPC: 5 / 99. pxx: **99 / 99** — the later decl wins the global const table, so
TA's methods silently read TB's value.

## Repro 2 — class const clobbers a GLOBAL

```pascal
const Size = 10;
type TA = class private const Size = 777; public function GetSize: Integer; end;
```
FPC: `writeln(Size)` in main = 10, `a.GetSize` = 777.
pxx: **777 / 777** — main's `Size` silently reads the class const.

Any codebase where two classes use the same private const name (`Max`,
`Size`, `DefaultCapacity`, `BufSize`...) — i.e. exactly what `private` invites
— miscompiles silently.

## Root

The class-body `const` section parses into the ordinary GLOBAL constant tables
(scalar Syms skConst / StrConst), keyed by bare name: no owning class, no
shadowing, later registration overwrites. `TFoo.MaxItems` qualified access
resolves the same global by name (parser ~3595 fallbacks).

## Fix direction

Scope them for real (this is name RESOLUTION, not just visibility):
1. Registry: ClassConstCi/NOff/NLen/Vis (+ value or backing global sym idx),
   stamped in the class-body const parse; STOP registering the bare name in the
   global tables (or register a mangled name, e.g. `TA.Max`).
2. Resolution inside a method body: bare `Max` looks up the enclosing class
   chain FIRST (own -> ancestors), then unit globals — FPC scoping order.
   Repro 2's main-body `Size` then finds only the global.
3. Qualified `TClass.Const` resolves via the registry (the existing ~3595
   class-qualified fallback becomes a registry hit).
4. Visibility: with the registry carrying Vis, EnforceMemberVis slots in for
   free at both access paths — burns tclass12b (`strict private const` from a
   descendant) under --strict-visibility/--mimic-fpc.
5. Typed/string class consts: StrConst table needs the same ownership or
   mangling treatment.

## Acceptance

Repro 1 prints 5/99 and repro 2 prints 10/777 (FPC-differential identical);
inherited class consts resolve up the parent chain; tclass12b rejected under
--strict-visibility; fpjson/Synapse/fgl + conformance pass-set stay green
(regression sweep — the resolution-order change is the risky part).

## Log
- 2026-07-15 — resolved, commit 9122d8cc.
