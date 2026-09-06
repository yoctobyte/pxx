program test_a_class_const_is_a_constant_in_an_out_of_line_method_header;
{ A class's own body is TWO ranges of source -- the declaration, and the
  out-of-line method implementations -- and Pascal requires a default parameter
  value to be written in BOTH. The class-const fold knew only the first range,
  so `procedure TC.A(V: Integer = K);` was refused with `not a constant` while
  the identical `procedure A(V: Integer = K);` inside the class body compiled:
  the same class, the same const, the same expression, accepted in one of the
  two places the language makes you write it.

  No new parser state was needed. defs.inc already declares MethImplOwnerCi for
  exactly this range, and the two other lookups that span both ranges --
  FindNestedType and alias visibility -- already consult the pair. The const
  fold consulted one.

  Rows 1-4 are the shape that was refused, across the spellings that reach the
  same chain: a class, a record, an inherited const, and a nested class.
  Row 5 is an expression over the const rather than the bare name.
  Rows 6-7 are the ranges that already worked and must keep working -- the
  in-body declaration default, and the const used inside a method BODY.
  bug-p-a-class-const-is-not-a-constant-in-an-out-of-line-method-header }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TC = class
  const
    K = 5;
  public
    procedure A(V: Integer = K);
    procedure E(V: Integer = K * 2 + 1);
    function InBody: Integer;
  end;

  TD = class(TC)
  public
    procedure Inh(V: Integer = K);
  end;

  TR = record
  const
    RK = 7;
    procedure R1(V: Integer = RK);
  end;

  TOuter = class
  type
    TInner = class
    const
      NK = 9;
      procedure N1(V: Integer = NK);
    end;
  end;

procedure TC.A(V: Integer = K);
begin WriteLn('1 ', V); end;

procedure TC.E(V: Integer = K * 2 + 1);
begin WriteLn('5 ', V); end;

function TC.InBody: Integer;
begin Result := K; end;

procedure TD.Inh(V: Integer = K);
begin WriteLn('3 ', V); end;

procedure TR.R1(V: Integer = RK);
begin WriteLn('2 ', V); end;

procedure TOuter.TInner.N1(V: Integer = NK);
begin WriteLn('4 ', V); end;

var c: TC; d: TD; r: TR; n: TOuter.TInner;
begin
  c := TC.Create;  c.A;  c.E;
  d := TD.Create;  d.Inh;
  r.R1;
  n := TOuter.TInner.Create; n.N1;
  WriteLn('6 ', c.InBody);
  WriteLn('7 ', TC.K, ' ', TR.RK);
end.
