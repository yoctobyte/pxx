{ A Variant written THROUGH A POINTER, on wasm32.

  The destination of a variant store arrives as an IR node, and IR_LOAD_SYM is
  two different questions wearing one opcode: a load of a VARIANT symbol is the
  variant itself (address = its slot), a load of a POINTER symbol is an address
  the program computed (address = the slot's VALUE). Dispatching on the opcode
  alone answered the first for both.

  Every row below avoids 0 and None as an expected value on purpose: those are
  what the defect PRODUCED, so a row expecting either would pass with the store
  doing nothing at all. }
program variantptr_slice;

type
  PVar = ^Variant;
  TR16 = record a, b: Int64; end;
  PR16 = ^TR16;

var
  v, src: Variant;
  pv, pv2: PVar;
  r, rsrc: TR16;
  pr: PR16;

{ The store must reach the pointee, not the pointer's own slot. }
procedure StoreInt(p: PVar);
begin p^ := 42; end;

procedure StoreStr(p: PVar);
begin p^ := 'through'; end;

procedure StoreFloat(p: PVar);
begin p^ := 2.5; end;

{ WasmVariantCopy takes BOTH operands through the same helper, so a
  variant-to-variant copy has the bug on each side independently. }
procedure CopyVar(dst, s: PVar);
begin dst^ := s^; end;

{ The shapes that must NOT change: a var/out parameter does not reach the
  pointer arm, and a fix in the other direction would break these. }
procedure ViaVarParam(var d: Variant);
begin d := 44; end;

procedure ViaOutParam(out d: Variant);
begin d := 45; end;

begin
  { pristine destination: the defect left the tag zeroed and this read None/0 }
  v := 0; StoreInt(@v);
  WriteLn('int-thru=', Integer(v));

  { LIVE destination: the defect wrote the payload where the tag belongs, so
    this row did not answer wrongly — it RAISED "variant holds an unknown tag".
    A value-only assertion cannot see that arm; this row is why the diff runs. }
  v := 99; StoreInt(@v);
  WriteLn('int-over-live=', Integer(v));

  v := 0; StoreStr(@v);
  WriteLn('str-thru=', string(v));

  v := 0; StoreFloat(@v);
  WriteLn('float-thru=', Double(v):0:2);

  { both operands through pointers }
  src := 4242; v := 0; pv := @v; pv2 := @src;
  CopyVar(pv, pv2);
  WriteLn('copy-thru=', Integer(v));

  { a variant READ through a pointer, as the source of a plain assignment }
  src := 77; pv2 := @src; v := pv2^;
  WriteLn('read-thru=', Integer(v));

  { must stay correct }
  v := 0; ViaVarParam(v);  WriteLn('var-param=', Integer(v));
  v := 0; ViaOutParam(v);  WriteLn('out-param=', Integer(v));
  v := 0; v := 46;         WriteLn('plain-sym=', Integer(v));

  { a 16-byte RECORD through a pointer was always correct — it lowers to a
    block copy and never reaches the variant helper. Here so that a fix which
    over-reaches into the generic pointer-store path fails loudly. }
  rsrc.a := 11; rsrc.b := 22; r.a := 1; r.b := 2;
  pr := @r; pr^ := rsrc;
  WriteLn('rec16-thru=', r.a, ' ', r.b);
end.
