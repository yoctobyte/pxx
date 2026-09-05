{ A class property backed by a CLASS VAR, reached through every spelling that is
  not `TypeName.Prop`.

  `TCls.V` already worked (bug-p-a-class-property-cannot-be-backed-by-a-class-var,
  first half). Five further sites resolved the accessor slot with FindUMeth and
  nothing else, so each refused with a diagnostic naming the lookup that failed
  rather than the one that was missing: the unqualified read and write inside a
  method (`V := 7`), the instance-qualified read and write (`a.V`, `Self.V`,
  a record variable's `r.Val`), and a `with` scope, which additionally could not
  see a bare class var at all.

  THE SHARING IS THE ASSERTION, AND THE INSTANCE FIELD BESIDE IT IS THE CONTROL.
  Every access below would also compile if the property were wired to
  per-instance storage -- one object, one slot, right answer for the wrong
  reason. So each write goes through ONE instance and each read comes back
  through ANOTHER, and `FPer` is an ordinary field written the same way in the
  same lines: the class var must show the second write and the field must not.
  A fix that reused the surrounding MakeAccessorCall shape against Self would
  print 5 where this file asks for 6, with no diagnostic.

  Expected output is fpc 3.2.2's own, byte for byte.
  bug-p-a-class-property-cannot-be-backed-by-a-class-var }
program test_class_property_through_an_instance;
{$mode delphi}

type
  TCls = class
  private
    FPer: LongInt;                 { the control: ordinary per-instance storage }
    { `class var` is a SECTION HEADER, not a modifier on one declaration, so
      FPer has to come BEFORE it or it becomes a class var too -- and then fpc
      rejects the instance property over it with "Illegal symbol for property
      access", which is how this file was first written. }
    class var FV: LongInt;
  public
    class property V: LongInt read FV write FV;
    property Per: LongInt read FPer write FPer;
    procedure PokeBare;            { unqualified write inside an instance method }
    function PeekBare: LongInt;    { unqualified read }
    procedure PokeSelf;            { Self-qualified write }
  end;

  TRec = record
  class var
    FVal: LongInt;
  class property Val: LongInt read FVal write FVal;
  end;

  { A CLASS HELPER is the shape that distinguishes the two keys a bare name can
    be looked up on: SelfMemberCi puts the helper in front when the helper
    declares the name, while CurMethClass is the method's own class. Two arms
    used to answer this question, one keyed on each; this row is what showed the
    CurMethClass-keyed arm covers the helper too, so the second could go rather
    than sit there working today and rotting quietly. }
  TBase = class end;
  TH = class helper for TBase
  private
    class var FH: LongInt;
  public
    class property H: LongInt read FH write FH;
    procedure PokeH;
    function PeekH: LongInt;
  end;

procedure TCls.PokeBare; begin V := 1; Per := 1; end;
function TCls.PeekBare: LongInt; begin PeekBare := V; end;
procedure TCls.PokeSelf; begin Self.V := 2; end;

procedure TH.PokeH; begin H := 8; end;
function TH.PeekH: LongInt; begin PeekH := H; end;

var
  a, b: TCls;
  r, s: TRec;
  h, k: TBase;
  x: LongInt;

begin
  a := TCls.Create;
  b := TCls.Create;

  { 1. unqualified inside a method: write through a, read back through b }
  a.PokeBare;
  WriteLn(b.PeekBare);                    { 1 -- shared }
  WriteLn(a.Per, ' ', b.Per);             { 1 0 -- the control, NOT shared }

  { 2. Self-qualified write, read through the other instance }
  a.PokeSelf;
  WriteLn(b.PeekBare);                    { 2 }

  { 3. instance-qualified write and read, crossing instances }
  a.V := 3;
  WriteLn(b.V);                           { 3 }
  b.V := 4;
  WriteLn(a.V);                           { 4 }

  { 4. the type spelling sees the same slot the instances wrote }
  WriteLn(TCls.V, ' ', TCls.FV);          { 4 4 }

  { 5. a with scope: the bare class var, and the property over it }
  with a do FV := 5;
  WriteLn(b.V);                           { 5 }
  with a do V := 6;
  with b do x := V;
  WriteLn(x);                             { 6 }
  WriteLn(TCls.FV);                       { 6 -- one slot, not a with-local copy }

  { 6. a RECORD's class property, through two separate record variables }
  r.Val := 41;
  WriteLn(s.Val);                         { 41 -- shared across variables }
  s.Val := 42;
  WriteLn(r.Val, ' ', TRec.FVal);         { 42 42 }

  { 7. through a CLASS HELPER's method, written on one instance and read on
    another -- the helper's class var is shared exactly like the class's is }
  h := TBase.Create;
  k := TBase.Create;
  h.PokeH;
  WriteLn(k.PeekH, ' ', TH.H);            { 8 8 }

  { 8. the three types keep three slots }
  WriteLn(TCls.V, ' ', TRec.Val, ' ', TH.H);   { 6 42 8 }
end.
