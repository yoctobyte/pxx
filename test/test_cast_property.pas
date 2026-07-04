program test_cast_property;
{ Property access through a class typecast: TDescendant(baseref).Prop.
  ParseClassRecordSelectors (the cast selector path) used to fall through to
  the raw field builder with the PROPERTY name, so RecFieldOffset found no
  field and read offset 0 — the VMT pointer (silent garbage). Covers
  field-backed and getter/setter-method-backed properties, inherited
  properties, writes through the cast, virtual getters, and indexed
  properties — the TButton(Sender).Caption pattern. }

type
  TP = class
  private
    FTag: Integer;
    FArr: array[0..3] of Integer;
    function GetDouble: Integer;
    procedure SetDouble(v: Integer);
    function GetItem(i: Integer): Integer;
    procedure SetItem(i: Integer; v: Integer);
    function GetVirt: Integer; virtual;
  public
    property Tag: Integer read FTag write FTag;                 { field-backed, base class }
    property Twice: Integer read GetDouble write SetDouble;    { method-backed }
    property Items[i: Integer]: Integer read GetItem write SetItem;  { indexed }
    property Virt: Integer read GetVirt;                        { virtual getter }
  end;
  TT = class(TP)
  private
    FOwn: Integer;
    function GetVirt: Integer; override;
  public
    property Own: Integer read FOwn write FOwn;                 { own field-backed }
  end;

var
  total, okc: Integer;

procedure Check(name: string; got, want: Integer);
begin
  total := total + 1;
  if got = want then
  begin
    okc := okc + 1;
    writeln('ok ', name);
  end
  else
    writeln('FAIL ', name, ' got=', got, ' want=', want);
end;

function TP.GetDouble: Integer;
begin
  GetDouble := FTag * 2;
end;

procedure TP.SetDouble(v: Integer);
begin
  FTag := v div 2;
end;

function TP.GetItem(i: Integer): Integer;
begin
  GetItem := FArr[i];
end;

procedure TP.SetItem(i: Integer; v: Integer);
begin
  FArr[i] := v;
end;

function TP.GetVirt: Integer;
begin
  GetVirt := 1;
end;

function TT.GetVirt: Integer;
begin
  GetVirt := 2;
end;

var
  t: TT;
  c: TP;
begin
  total := 0; okc := 0;
  t := TT.Create;
  t.FTag := 99;
  t.FOwn := 55;
  c := t;

  Check('cast-field-direct', TT(c).FTag, 99);
  Check('cast-inherited-prop-read', TT(c).Tag, 99);
  Check('cast-own-prop-read', TT(c).Own, 55);
  Check('noncast-prop-read', t.Tag, 99);

  TT(c).Tag := 41;
  Check('cast-prop-write', t.FTag, 41);
  TT(c).Own := 7;
  Check('cast-own-prop-write', t.FOwn, 7);

  Check('cast-getter-method', TT(c).Twice, 82);
  TT(c).Twice := 100;
  Check('cast-setter-method', t.FTag, 50);

  TT(c).Items[2] := 33;
  Check('cast-indexed-write', t.FArr[2], 33);
  Check('cast-indexed-read', TT(c).Items[2], 33);

  Check('cast-virtual-getter', TT(c).Virt, 2);   { dynamic type wins }
  Check('base-virtual-getter', c.Virt, 2);

  t.FTag := 99;
  Check('grouped-prop-read', (t).Tag, 99);          { grouped-expr sibling path }
  Check('grouped-getter-method', (t).Twice, 198);
  Check('as-cast-prop-read', (c as TT).Tag, 99);

  t.Free;
  writeln('total ok ', okc, ' / ', total);
end.
