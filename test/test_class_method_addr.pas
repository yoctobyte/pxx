{ `@TClass.Method` — a method's raw CODE address reached through the TYPE name
  rather than an instance, in both an expression and a record constant.

  With no object there is nothing to dispatch on, so this yields the STATIC
  address of that class's own implementation even for a virtual method — which
  is the whole point of the idiom: it is how a VMT is built by hand.
  rtl-generics' Generics.Defaults fills its IComparer VMT records exactly this
  way (`@TRawInterface._AddRef`), which is where this gap was found.

  Before this, `@` never reached the decision — a class TYPE is not in the sym
  table, so the name fell through to the lvalue path and taking an address was
  diagnosed as `cannot call non-static method on class type directly`.

  The addresses are checked by CALLING through them, not for being non-nil: a
  plausible wrong address passes a non-nil test. TB.Virt must answer 22 and
  TD.Virt 33 — i.e. each class's own body, not a VMT lookup and not the base's.
  All values verified identical to fpc 3.2.2 -O1 -Mobjfpc.
}
program test_class_method_addr;

type
  TB = class
    function Inst: LongInt;
    function Virt: LongInt; virtual;
  end;
  TD = class(TB)
    function Virt: LongInt; override;
  end;
  TSelfFn = function(s: TB): LongInt;
  TVMT = record A: Pointer; B: Pointer; N: Integer; end;

function TB.Inst: LongInt; begin Result := 11; end;
function TB.Virt: LongInt; begin Result := 22; end;
function TD.Virt: LongInt; begin Result := 33; end;

const
  V: TVMT = (A: @TB.Inst; B: @TD.Virt; N: 99);

var
  o: TB; d: TD; f: TSelfFn;

begin
  o := TB.Create;
  d := TD.Create;

  { expression form }
  f := TSelfFn(@TB.Inst); writeln('inst ', f(o));
  f := TSelfFn(@TB.Virt); writeln('virt ', f(o));
  f := TSelfFn(@TD.Virt); writeln('dvirt ', f(d));

  { record-constant form: the same addresses, resolved at compile time }
  f := TSelfFn(V.A); writeln('const-inst ', f(o));
  f := TSelfFn(V.B); writeln('const-dvirt ', f(d));
  writeln('n ', V.N);
end.
