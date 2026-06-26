# Object-reference array identity lookup fails in Eliah palette icon handler

- **Type:** bug (compiler/runtime suspicion)
- **Track:** A (Pascal compiler/codegen) — found by Track B while attempting
  `feature-eliah-component-tabbar`
- **Opened:** 2026-06-26

## Symptom

Track B attempted a registry-driven Eliah component tab bar using existing PCL
`TButton`s. The clean dispatch shape was:

```pascal
type
  TEliahForm = class(TForm)
  public
    PaletteIconBtns: array of TButton;
    PaletteIconNames: array of AnsiString;
    procedure OnPaletteIcon(Sender: TObject);
  end;

procedure TEliahForm.OnPaletteIcon(Sender: TObject);
var i: Integer;
begin
  for i := 0 to Length(PaletteIconBtns) - 1 do
    if Sender = PaletteIconBtns[i] then
    begin
      ArmPaletteClass(PaletteIconNames[i]);
      Exit;
    end;
end;
```

The smoke drove it directly:

```pascal
EliahForm.OnPaletteTabNonVisual(nil);
{ ci is the slot whose PaletteIconNames[ci] = 'TTimer' }
EliahForm.OnPaletteIcon(EliahForm.PaletteIconBtns[ci]);
```

Expected: `OnPaletteIcon` finds the matching button instance, sets
`Palette.ItemIndex` to the `TTimer` combo row, and arms sticky Place.

Actual on pinned v81: the direct call returned without selecting `TTimer`;
Eliah smoke failed with:

```text
SMOKE FAIL: non-visual icon did not select TTimer
```

The attempted Track B feature was reverted. Do **not** add an Eliah-side
workaround; the component tab bar should stay on the clean object-identity
dispatch path once this is understood.

## Why it matters

This is ordinary object-reference identity logic: a stored object reference is
passed back as `Sender`, then compared against the same object-reference array.
PCL/Eliah event routing naturally wants this shape for toolbar/icon dispatch,
tabs, command surfaces, and future component palettes.

If object identity fails only when the references live in class-field dynamic
arrays, Track B will keep hitting it in idiomatic UI code.

## Repro ladder for Track A

Start with the smallest Pascal-only case, then add complexity only until it
reproduces:

1. Local dynamic array of `TObject`; pass `arr[i]` to a method; compare
   `Sender = arr[i]`.
2. Class field dynamic array of `TObject`; same comparison inside a method.
3. Field array of a subclass (`TButton`) compared against a base-typed
   `Sender: TObject`.
4. Parallel field arrays (`array of TButton`, `array of AnsiString`) where the
   match reads the parallel string slot after the equality succeeds.
5. Full PCL `TButton` allocation only if the pure object cases pass.

Candidate minimized shape:

```pascal
program repro_object_ref_array_identity;

type
  TObject = class
  end;

  TButton = class(TObject)
  end;

  TForm = class
  public
    Btns: array of TButton;
    Names: array of AnsiString;
    Hit: AnsiString;
    procedure Click(Sender: TObject);
  end;

procedure TForm.Click(Sender: TObject);
var i: Integer;
begin
  Hit := '';
  for i := 0 to Length(Btns) - 1 do
    if Sender = Btns[i] then
    begin
      Hit := Names[i];
      Exit;
    end;
end;

var f: TForm;
begin
  f := TForm.Create;
  SetLength(f.Btns, 2);
  SetLength(f.Names, 2);
  f.Btns[0] := TButton.Create;
  f.Btns[1] := TButton.Create;
  f.Names[0] := 'A';
  f.Names[1] := 'B';
  f.Click(f.Btns[1]);
  if f.Hit <> 'B' then Halt(1);
end.
```

## Acceptance

A minimized repro passes on x86-64 with the pinned compiler after the fix. Track
B can then implement `feature-eliah-component-tabbar` with direct object-identity
dispatch, no caption/string fallback and no slot-id workaround.
