# Virtual dispatch hits the wrong VMT slot with many mixed-signature methods

- **Type:** bug (codegen / VMT) — silent wrong call, heap corruption
- **Status:** urgent (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** Classes work ([[feature-own-net-http-lib]]) — `TStrings`/
  `TStringList`. Blocks the abstract-base collection pattern.

## Symptom

A class with **many virtual methods of mixed signatures** (functions returning
`string` / `Integer` / `TObject`, plus procedures with `string`/`TObject` params)
dispatches the **wrong VMT slot** for at least the first (string-returning)
method: it returns garbage (reads VMT/RTTI memory as a string → corrupted length
→ heap dump / segfault). Other slots (e.g. the `Integer` getter) dispatch
correctly, so it is a per-slot offset error, not total breakage.

## Repro (self-contained, no uses)

```pascal
program p;
type
  TB = class
    function GetA(i: Integer): string; virtual; abstract;
    function GetCount: Integer; virtual; abstract;
    function GetObj(i: Integer): TObject; virtual; abstract;
    procedure PutA(i: Integer; const s: string); virtual; abstract;
    procedure PutObj(i: Integer; o: TObject); virtual; abstract;
    procedure ClearIt; virtual; abstract;
    procedure DelIt(i: Integer); virtual; abstract;
    procedure InsIt(i: Integer; const s: string); virtual; abstract;
  end;
  TD = class(TB) F: array of string; N: Integer;
    function GetA(i: Integer): string; override;
    function GetCount: Integer; override;
    function GetObj(i: Integer): TObject; override;
    procedure PutA(i: Integer; const s: string); override;
    procedure PutObj(i: Integer; o: TObject); override;
    procedure ClearIt; override;
    procedure DelIt(i: Integer); override;
    procedure InsIt(i: Integer; const s: string); override;
  end;
{ ... trivial bodies; InsIt appends to F, GetA returns F[i], GetCount returns N }
var d: TD;
begin
  d := TD.Create; d.InsIt(0,'banana'); d.InsIt(1,'apple');
  writeln('count=', d.GetCount, ' [', d.GetA(1), ']');
end.
```
→ `count=2` (correct) but `GetA(1)` is garbage (dumps the VMT/RTTI), not `apple`.

Not abstract-specific: the same shape with `virtual` + empty bodies (not
`abstract`) breaks identically. So it is the **VMT layout/dispatch**, not the
abstract stub.

## Narrowing (done)

- 2 virtual methods, any signatures → **OK**.
- N uniform-signature methods (all `function(Integer): string`) up to 8 → **OK**.
- N alternating `function:string` / `procedure(Integer)` up to 6 → **OK**.
- The 8-method **mixed** set above (string/Integer/TObject returns + string/
  TObject-param procedures) → **first string getter mis-dispatches.**

So the trigger is a richer mix of return types and **managed (string/TObject)
parameters/returns** across enough slots — the VMT slot index or the call
lowering for the managed-return method is computed wrong in that layout. Track A
can bisect fastest by dumping the emitted VMT vs the call-site slot index.

## Why it matters

Blocks the standard `TStrings` (abstract Get/GetCount/GetObject/Put/PutObject +
Clear/Delete/Insert) → `TStringList` pattern — i.e. the whole classic Classes
collection surface, and any similar abstract-base polymorphic class. `TList`
(few, uniform-ish methods) is unaffected and works.

## Done when

- The repro prints `count=2 [apple]`; mixed-signature virtual/abstract method
  tables dispatch every slot correctly.
- Regression test under `make test` (the 8-mixed-method shape + a managed-return
  override called polymorphically).
- Self-host fixedpoint byte-identical; `make stabilize` + `make pin` so Track B
  can finish `TStrings`/`TStringList`.
