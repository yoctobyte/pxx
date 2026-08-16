{ Non-ordinal field values in a typed record constant: a string literal, `@var`,
  and `@proc` (both as a raw Pointer and as a procedural type).

  These reach init kinds 1 / 2 / 4, which the emitter has always implemented and
  the C frontend has always produced for struct initializers -- the Pascal
  record-constant path was simply never wired to them. Before that wiring,
  ConstEval could neither evaluate NOR consume these tokens, so the field loop
  desynced and reported `expected field name in record constant` against the
  VALUE, which read as a parser bug rather than a missing value form.

  Values are checked by dereferencing, not merely for being non-nil: `@g` must
  name g's actual storage and `@Foo` must be callable, which a plausible-looking
  wrong address would pass. Output verified identical to fpc 3.2.2 -O1 -Mobjfpc.

  Covers both the GLOBAL const path and the routine-LOCAL one, which use separate
  emitters (CompilePendingGlobalInits / CompilePendingLocalInits) and so are two
  independent places the same value form has to be understood.
}
program test_record_const_addr_field;

type
  TP = procedure;
  TRec = record
    S: AnsiString;
    A: Pointer;
    F: TP;
    N: Integer;
  end;

var
  g: Integer = 42;

procedure Foo;
begin
  writeln('called');
end;

const
  V: TRec = (S: 'hello'; A: @g; F: @Foo; N: 7);

procedure LocalConst;
type
  TL = record A: Pointer; N: Integer; end;
const
  L: TL = (A: @g; N: 9);
begin
  writeln('local ', PInteger(L.A)^, ' ', L.N);
end;

begin
  writeln(V.S, ' ', PInteger(V.A)^, ' ', V.N);
  V.F();
  LocalConst;
end.
