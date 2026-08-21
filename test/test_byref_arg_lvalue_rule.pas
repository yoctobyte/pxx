{ The by-ref argument rule: only an explicit `var`/`out` needs a true lvalue.

  The guard used to answer that question with a list of TYPE KINDS, extended
  once per aggregate after a user hit the refusal — by-value/`const` record,
  `const Variant`, promotable int, fixed-array call result, and finally
  interfaces. A constructor-call node carries the CLASS kind and an explicit
  `IFoo(o)` cast carries neither, so no length of type-kind list could ever have
  covered them: `TakeVal(TFoo.Create)` was refused with `by-reference argument
  must be a variable` while `TakeVal(o)` on a class variable compiled. FPC
  accepts all of it.

  Every row below is `fpc -O- -Mobjfpc` 3.2.2's answer. The `var`/`out` refusals
  are asserted separately, in test_byref_arg_lvalue_refused.pas, because a
  compile-time refusal cannot share a program with the shapes that must compile.

  bug-a-a-non-lvalue-is-refused-as-an-interface-argument }
program test_byref_arg_lvalue_rule;
{$mode objfpc}{$H+}

type
  IFoo = interface
    ['{11111111-1111-1111-1111-111111111111}']
    function Tag: Integer;
  end;

  TFoo = class(TInterfacedObject, IFoo)
    function Tag: Integer;
  end;

  TBig = record
    a, b, c: Int64;      { >8 bytes: by-ref for ABI only }
    tag: Integer;
  end;

  TFixed = array[0..3] of Integer;

var
  pass, fail: Integer;
  o: TFoo;

function TFoo.Tag: Integer; begin Result := 7; end;

function MakeFoo: IFoo;             begin Result := TFoo.Create; end;
function MakeBig: TBig;             begin Result.a := 1; Result.tag := 42; end;
function MakeFixed: TFixed;         begin Result[0] := 5; Result[3] := 8; end;

function TakeIfaceVal(a: IFoo): Integer;          begin Result := a.Tag; end;
function TakeIfaceConst(const a: IFoo): Integer;  begin Result := a.Tag; end;
function TakeBigVal(a: TBig): Integer;            begin Result := a.tag; end;
function TakeBigConst(const a: TBig): Integer;    begin Result := a.tag; end;
function TakeFixedConst(const a: TFixed): Integer; begin Result := a[0] + a[3]; end;
function TakeVarConst(const v: Variant): Integer;  begin Result := Integer(v) * 2; end;

procedure Chk(const what: AnsiString; got, want: Integer);
begin
  if got = want then begin Inc(pass); writeln('ok   ', what, ' = ', got); end
  else begin Inc(fail); writeln('FAIL ', what, ' = ', got, ' want ', want); end;
end;

begin
  pass := 0; fail := 0;
  o := TFoo.Create;

  { The shapes that already worked — they must keep working. }
  Chk('iface: class variable',        TakeIfaceVal(o), 7);
  Chk('iface: const class variable',  TakeIfaceConst(o), 7);
  Chk('iface: function result',       TakeIfaceVal(MakeFoo), 7);
  Chk('iface: const function result', TakeIfaceConst(MakeFoo), 7);

  { The shapes this ticket unblocked. }
  Chk('iface: constructor result',       TakeIfaceVal(TFoo.Create), 7);
  Chk('iface: const constructor result', TakeIfaceConst(TFoo.Create), 7);
  Chk('iface: explicit cast',            TakeIfaceVal(IFoo(o)), 7);
  Chk('iface: const explicit cast',      TakeIfaceConst(IFoo(o)), 7);

  { The four aggregates whose special cases the one rule replaced. }
  Chk('record: by-value call result',  TakeBigVal(MakeBig), 42);
  Chk('record: const call result',     TakeBigConst(MakeBig), 42);
  Chk('fixed array: const call result', TakeFixedConst(MakeFixed), 13);
  Chk('const Variant: literal',        TakeVarConst(21), 42);

  writeln('total ok ', pass, ' / ', pass + fail);
end.
