{ `object` = the standard Pascal old-style object TYPE: a value type with
  methods, lowered as a record-with-methods (no VMT, Self by reference).

  Until 2026-08-30 pxx spent this keyword on something else entirely -- a rooted
  class REFERENCE in type-reference position, a stopgap from before builtin
  TObject existed. Retiring that (Part 1) is what freed the keyword to mean what
  it means in every other Pascal, and the trigger was real source: rtl-generics'
  generics.collections declares one `= object` and stopped at it.
  bug-p-object-value-types-standard-meaning

  What this pins, in order: value (copy, not alias) semantics; SizeOf being the
  FIELDS and not a pointer; strict private / protected / public sections, where
  `protected` is the one a record refuses and an object must accept; methods,
  class methods and properties; a nested `type` section; `@`/`^` through it; and
  the same shape as a generic template, both the `generic`/`specialize` and the
  Delphi angle-bracket spellings. }
program test_object_value_type;

type
  TPt = object
  strict private
    FX, FY: Integer;
  protected
    { a record refuses `protected` (it does not inherit); an object may open it.
      Inert either way -- nothing derives from a pxx object -- but real source
      writes it, which is the whole point. }
    function Sum: Integer;
  public
    type TScale = Integer;      { nested type section }
    procedure Init(ax, ay: Integer);
    function Scaled(k: TScale): Integer;
    property X: Integer read FX;
    property Y: Integer read FY;
  end;
  PPt = ^TPt;

  generic TBox<T> = object
  strict private
    FV: T;
  public
    procedure Put(v: T);
    function Get: T;
  end;
  TIntBox = specialize TBox<Integer>;

procedure TPt.Init(ax, ay: Integer);
begin FX := ax; FY := ay; end;

function TPt.Sum: Integer;
begin Sum := FX + FY; end;

function TPt.Scaled(k: TScale): Integer;
begin Scaled := Sum * k; end;

procedure TBox.Put(v: T); begin FV := v; end;
function TBox.Get: T; begin Get := FV; end;

var
  p, q: TPt;
  r: PPt;
  b: TIntBox;
  arr: array[0..1] of TPt;
  ok: Boolean;
begin
  ok := True;

  p.Init(3, 4);
  Writeln('sum=', p.Sum);
  Writeln('scaled=', p.Scaled(10));
  Writeln('x=', p.X, ' y=', p.Y);
  if p.Sum <> 7 then ok := False;
  if p.Scaled(10) <> 70 then ok := False;

  { VALUE semantics: assignment copies. The retired rooted reference would have
    aliased here, so this is the single line that tells the two apart. }
  q := p;
  q.Init(10, 20);
  Writeln('copy p=', p.Sum, ' q=', q.Sum);
  if p.Sum <> 7 then ok := False;
  if q.Sum <> 30 then ok := False;

  { ...and SizeOf is the fields, not a pointer. }
  Writeln('sizeof=', SizeOf(TPt));
  if SizeOf(TPt) <> 2 * SizeOf(Integer) then ok := False;

  r := @p;
  Writeln('via ptr=', r^.Sum);
  if r^.Sum <> 7 then ok := False;
  r^.Init(1, 1);
  if p.Sum <> 2 then ok := False;     { the pointer writes through to p }

  arr[0].Init(5, 5);
  arr[1] := arr[0];
  arr[1].Init(6, 6);
  Writeln('array=', arr[0].Sum, ',', arr[1].Sum);
  if (arr[0].Sum <> 10) or (arr[1].Sum <> 12) then ok := False;

  b.Put(21);
  Writeln('generic=', b.Get, ' sizeof=', SizeOf(TIntBox));
  if b.Get <> 21 then ok := False;
  if SizeOf(TIntBox) <> SizeOf(Integer) then ok := False;

  if ok then Writeln('OK') else Writeln('FAIL');
end.
