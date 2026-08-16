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
    { Both halves of the single-char ambiguity, deliberately side by side: the
      SAME literal 'Z' is a string in one field and an ORDINAL in the other, so
      the value form can only be chosen by the destination type. Keying on the
      token instead compiled cleanly and stored the wrong bytes in C
      (test_typed_const_record went red on exactly this). }
    C: Char;
    S1: AnsiString;
  end;

var
  g: Integer = 42;

procedure Foo;
begin
  writeln('called');
end;

type
  TEnt = record Sel: Boolean; P: Pointer; end;

const
  V: TRec = (S: 'hello'; A: @g; F: @Foo; N: 7; C: 'Z'; S1: 'Z');

  { SCALAR typed const taking an address -- `Comparer_Int8_Instance: Pointer =
    @Comparer_Int8_VMT` in rtl-generics. }
  PG: Pointer = @g;
  PF: Pointer = @Foo;

  { ARRAY-of-record const with @ field values -- the sibling of the scalar
    record path above; rtl-generics' ComparerInstances is exactly this shape. }
  ENTS: array[0..1] of TEnt = (
    (Sel: True;  P: @g),
    (Sel: False; P: @Foo)
  );

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
  writeln('char ', V.C, ' str ', V.S1, ' len ', Length(V.S1));
  V.F();
  writeln('scalar ', PInteger(PG)^, ' ', PtrUInt(PF) = PtrUInt(V.F));
  writeln('arr ', ENTS[0].Sel, ' ', PInteger(ENTS[0].P)^, ' ', ENTS[1].Sel, ' ',
          PtrUInt(ENTS[1].P) = PtrUInt(V.F));
  LocalConst;
end.
