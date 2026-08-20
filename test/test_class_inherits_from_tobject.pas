{ Every class descends from TObject, but nothing said so at RUN TIME: the RTTI
  blob of a root class carried a nil parent, so the chain the runtime walks
  stopped one link short of TObject.

    b := TBase.Create;
    writeln(b is TObject);                { was FALSE   FPC: TRUE }
    writeln(TBase.InheritsFrom(TObject)); { was FALSE   FPC: TRUE }

  and, the symptom that actually loses a program:

    try raise Exception.Create('z') except
      on E: TObject do writeln('caught');   { never fired -- the exception
    end;                                      escaped as UNHANDLED and the
                                              process aborted }

  `TDer.InheritsFrom(TBase)` was right all along, which is what hid it: only the
  IMPLICIT root link was missing. `class(TObject)` spelled explicitly was equally
  affected, because RegisterBuiltinTObject deliberately leaves such a class at
  parentCi = -1 so that no VMT relocates. The fix links the blob's PARENT word,
  which is RTTI rather than layout, so the implicit-root VMT model is untouched.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-p-a-class-does-not-inherit-from-tobject-at-run-time }
program test_class_inherits_from_tobject;
{$mode objfpc}{$H+}
uses sysutils;

type
  TRoot = class end;
  TExplicit = class(TObject) end;
  TDer = class(TRoot) end;
  TDer2 = class(TDer) end;
  EMine = class(Exception) end;
  IFoo = interface procedure Bar; end;
  TFoo = class(TInterfacedObject, IFoo) procedure Bar; end;

procedure TFoo.Bar; begin end;

var
  ok, total: Integer;
  r: TRoot; e: TExplicit; d: TDer2; o: TObject; caught: string;

procedure Chk(const what: string; got, want: Boolean);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

procedure ChkS(const what, got, want: string);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got [', got, '] want [', want, ']');
end;

begin
  ok := 0; total := 0;
  r := TRoot.Create; e := TExplicit.Create; d := TDer2.Create;

  { ---- the implicit root link ---- }
  Chk('TRoot.InheritsFrom(TObject)', TRoot.InheritsFrom(TObject), True);
  Chk('TExplicit.InheritsFrom(TObject)', TExplicit.InheritsFrom(TObject), True);
  Chk('TDer.InheritsFrom(TObject)', TDer.InheritsFrom(TObject), True);
  Chk('TDer2.InheritsFrom(TObject)', TDer2.InheritsFrom(TObject), True);
  Chk('r.InheritsFrom(TObject)', r.InheritsFrom(TObject), True);
  Chk('r is TObject', r is TObject, True);
  Chk('e is TObject', e is TObject, True);
  Chk('d is TObject', d is TObject, True);

  { ---- and it did not break the links that already worked ---- }
  Chk('TRoot.InheritsFrom(TRoot)', TRoot.InheritsFrom(TRoot), True);
  Chk('TDer2.InheritsFrom(TDer)', TDer2.InheritsFrom(TDer), True);
  Chk('TDer2.InheritsFrom(TRoot)', TDer2.InheritsFrom(TRoot), True);
  Chk('TRoot.InheritsFrom(TDer)', TRoot.InheritsFrom(TDer), False);
  Chk('TObject.InheritsFrom(TObject)', TObject.InheritsFrom(TObject), True);
  Chk('d is TDer', d is TDer, True);
  Chk('r is TDer', r is TDer, False);
  Chk('TRoot.InheritsFrom(TExplicit)', TRoot.InheritsFrom(TExplicit), False);

  { ---- a TObject-typed variable still reports its real class ---- }
  o := d;
  ChkS('o.ClassName', o.ClassName, 'TDer2');
  Chk('o is TDer2', o is TDer2, True);
  Chk('o is TRoot', o is TRoot, True);
  Chk('(o as TRoot) is TObject', (o as TRoot) is TObject, True);

  { ---- the symptom that loses a program: a catch-all handler ---- }
  caught := 'none';
  try
    raise Exception.Create('z');
  except
    on E: TObject do caught := 'TObject:' + E.ClassName;
  end;
  ChkS('on E: TObject', caught, 'TObject:Exception');

  caught := 'none';
  try
    raise EMine.Create('y');
  except
    on E: EMine do caught := 'EMine';
    on E: TObject do caught := 'TObject';
  end;
  ChkS('specific still wins', caught, 'EMine');

  { ---- an INTERFACE does not descend from TObject, and its implementor does ---- }
  Chk('TFoo is TObject', TFoo.Create is TObject, True);
  Chk('TFoo.InheritsFrom(TObject)', TFoo.InheritsFrom(TObject), True);

  writeln('total ok ', ok, ' / ', total);
end.
