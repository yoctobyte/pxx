program test_class_overload_directive_b247;
{ `overload` is a real TOKEN (tkOverload); every other method directive is a plain
  identifier. The class-body directive loop only matched tkIdent, so it walked past
  `overload` — harmless for a lone trailing `overload;`, but in
  `reintroduce; overload; virtual;` it left `virtual` to be parsed as a FIELD name,
  which demands ':' and died on the ';'
  (bug-pascal-class-body-overload-directive). fpcunit declares its constructors
  exactly that way. }
type
  TBase = class
    constructor Create; reintroduce; overload; virtual;
    procedure Ping; virtual;
    function Tag: string; virtual;
  end;

  TDerived = class(TBase)
    procedure Ping; override;
    function Tag: string; override;
  end;

var lastName: string;

constructor TBase.Create;
begin
  lastName := '<none>';
end;

procedure TBase.Ping;
begin
  writeln('base ping');
end;

function TBase.Tag: string;
begin
  Tag := 'base';
end;

procedure TDerived.Ping;
begin
  writeln('derived ping');
end;

function TDerived.Tag: string;
begin
  Tag := 'derived';
end;

var
  b: TBase;
  d: TDerived;
begin
  b := TBase.Create;
  writeln('name=', lastName);
  b.Ping;
  writeln('tag=', b.Tag);
  b.Free;

  d := TDerived.Create;
  d.Ping;
  writeln('tag=', d.Tag);
  d.Free;
end.
