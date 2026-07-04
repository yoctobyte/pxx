program test_forward_class_base;
{ Forward class decl `TFoo = class;` + full decl that ADDS A BASE must attach
  the base and fields to the stub's entry — a second AddUClass shadowed it
  (FindUClass returns the first match), making the fields invisible and the
  metaclass alias point at an empty rootless class. Covers the
  metaclass-before-decl idiom and mutual references through a forward. }

type
  TBase = class
    FB: Integer;
  end;
  TFoo = class;                 { forward — no base }
  TFooClass = class of TFoo;    { aliases the stub's entry }
  TFoo = class(TBase)           { full — adds a base }
  private
    FVal: Integer;
  public
    constructor Create;
    function Sum: Integer;
  end;

  TNode = class;
  TTree = class
    FRoot: TNode;
    procedure SetRoot(n: TNode);
  end;
  TNode = class(TObject)        { explicit-root full decl after forward }
    FOwner: TTree;
    FVal: Integer;
    function Describe: Integer; virtual;
  end;
  TLeaf = class(TNode)
    function Describe: Integer; override;
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

constructor TFoo.Create;
begin
  FVal := 7;
  FB := 3;
end;

function TFoo.Sum: Integer;
begin
  Sum := FVal + FB;
end;

procedure TTree.SetRoot(n: TNode);
begin
  FRoot := n;
  n.FOwner := Self;
end;

function TNode.Describe: Integer;
begin
  Describe := FVal;
end;

function TLeaf.Describe: Integer;
begin
  Describe := FVal * 2;
end;

var
  f: TFoo;
  t: TTree;
  n: TNode;
  isb: Integer;
begin
  total := 0; okc := 0;

  f := TFoo.Create;
  Check('own-field', f.FVal, 7);
  Check('inherited-field', f.FB, 3);
  Check('method-both-fields', f.Sum, 10);
  isb := 0; if f is TBase then isb := 1;
  Check('is-base', isb, 1);
  f.Free;

  t := TTree.Create;
  n := TLeaf.Create;
  n.FVal := 21;
  t.SetRoot(n);
  Check('virtual-through-forward', t.FRoot.Describe, 42);
  isb := 0; if t.FRoot.FOwner = t then isb := 1;
  Check('mutual-ref', isb, 1);
  n.Free; t.Free;

  writeln('total ok ', okc, ' / ', total);
end.
