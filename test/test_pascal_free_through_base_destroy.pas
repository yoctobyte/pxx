program test_pascal_free_through_base_destroy;
{ `Free` through a BASE-class reference must run the descendant's Destroy.

  The Free desugar decided whether to emit a Destroy call from the receiver's
  STATIC class: `if FindUMeth(ci, 'Destroy') >= 0`. A base that declares no
  destructor has no Destroy member, so nothing was emitted at all — not a
  non-virtual call, an ABSENT one. Only the memory was freed, and every managed
  field the descendant's Destroy would have released stayed released-never. No
  diagnostic; ordinary virtuals through the same reference were fine.

  TObject now carries a Destroy row bound to an empty default body, filling the
  reserved root VMT slot 0, so Free is an ordinary virtual dispatch and lands on
  the override. Every line below is checked against `fpc -Mobjfpc`.

  NOT covered here: --compact-classes, which has no reserved root slots and
  keeps the parse-time behaviour by design (the low-memory mode's documented
  limit). The Makefile asserts that path separately. }

type
  TBase = class
    procedure Hello; virtual;
  end;

  TMid = class(TBase)
    destructor Destroy; override;
  end;

  TDer = class(TMid)
    s: string;
    destructor Destroy; override;
    procedure Hello; override;
  end;

  { no destructor anywhere in the chain — the empty default body must run and
    do nothing, which is the row that proves slot 0 is never nil }
  TPlain = class
    v: Integer;
  end;

procedure TBase.Hello; begin WriteLn('base'); end;
procedure TDer.Hello;  begin WriteLn('der'); end;

destructor TMid.Destroy;
begin
  WriteLn('TMid.Destroy');
  inherited Destroy;
end;

destructor TDer.Destroy;
begin
  WriteLn('TDer.Destroy ', s);
  inherited Destroy;
end;

var
  b: TBase;
  o: TObject;
  m: TMid;
  d: TDer;
  p: TPlain;

begin
  { the bug: a TBase reference, TBase declares no destructor }
  b := TDer.Create; TDer(b).s := 'q';
  b.Hello;
  b.Free;
  WriteLn('--1');

  { ...and through a static TObject, the widest possible reference }
  o := TDer.Create; TDer(o).s := 'r';
  o.Free;
  WriteLn('--2');

  { through the MIDDLE class, which DOES declare one: the chain must not run
    twice, and must still start at TDer }
  m := TDer.Create; TDer(m).s := 't';
  m.Free;
  WriteLn('--3');

  { through the exact class — the spelling that always worked }
  d := TDer.Create; d.s := 'u';
  d.Free;
  WriteLn('--4');

  { a class with no destructor at all: the default body runs and prints nothing }
  p := TPlain.Create; p.v := 1;
  p.Free;
  WriteLn('--5');

  { a bare TMid instance: its own Destroy, then TBase's implicit root one }
  m := TMid.Create;
  m.Free;
  WriteLn('--6');

  { Free on nil is still a no-op, not a dispatch through a nil VMT }
  b := nil;
  b.Free;
  WriteLn('--7');
end.
