{ EVERY SHAPE A COMPARISON OPERAND CAN TAKE, and whether it is a STRING.

  One predicate decides this on wasm32 -- WasmCompareOperandType -- and it is
  the only place in that backend where "what type is this operand" has two
  plausible answers that disagree. A node's RESULT type comes from the symbol
  or the callee; the IR's own TAG records what the expression MEANT. They agree
  almost always, and the rows below are the places they can come apart:

    p^ = b        the load is over a POINTER symbol and the tag says string
                  -- the tag must WIDEN, or this compares two addresses
    @a = @b       the LEA is over a STRING symbol and the tag says pointer
                  -- the tag must NARROW, or this compares characters
    Pointer(s)    an IR_LOAD_SYM over an ANSISTRING symbol, tag tyPointer
                  -- the cast is the whole expression, and the symbol is
                     answering a question nobody asked

  The third one is why this file exists. `Pointer(s) = nil` is `pystr_is_none`
  in the RTL, which is how every NilPy `is None` test is answered, and it
  refused to lower on wasm32 as `string operand of type Pointer` plus
  `` `=` on strings `` -- a pointer comparison turned away as a string one --
  because the predicate let the tag widen and not narrow.

  A cross test rather than a wasm32 one because the register backends have no
  such predicate: they never ask, so they cannot get it wrong, and a row that
  can only fail on one target is still worth running on six -- the value it
  asserts is the language's, not the backend's.

  BOTH DIRECTIONS ON EVERY COMPARABLE ROW. A one-directional row cannot tell a
  working comparison from one that answers TRUE unconditionally, and comparing
  addresses instead of contents answers TRUE for `a = a` -- which is exactly
  what a repro writes. `AddrEq` is the row that must answer TRUE for the same
  variable twice and FALSE for two equal-valued distinct ones; content and
  address compares disagree on precisely that pair.

  IsNil's second row passes the EMPTY string, because an empty AnsiString has
  a nil handle: the two rows there are `a real string is not nil` and `an empty
  one is`, and a predicate that always said "string compare" answered neither. }
program test_cross_compare_operand_shapes;
type TR = record f: AnsiString; g: string[8]; end;
function F(k: Integer): AnsiString; begin if k = 0 then F := 'ab' else F := 'zz'; end;
function EqA(const a, b: AnsiString): Boolean; begin EqA := a = b; end;
function LtA(const a, b: AnsiString): Boolean; begin LtA := a < b; end;
function EqF(const a, b: string[8]): Boolean; begin EqF := a = b; end;
function LtF(const a, b: string[8]): Boolean; begin LtF := a < b; end;
function DerefEq(p: ^string[8]; const b: string[8]): Boolean; begin DerefEq := p^ = b; end;
function AddrEq(const a, b: string[8]): Boolean; begin AddrEq := @a = @b; end;
function CallEq(k: Integer): Boolean; begin CallEq := F(k) = 'ab'; end;
function ConcatEq(const a, b: AnsiString): Boolean; begin ConcatEq := a + b = 'ab'; end;
function FieldEqA(const r: TR): Boolean; begin FieldEqA := r.f = 'ab'; end;
function FieldEqF(const r: TR): Boolean; begin FieldEqF := r.g = 'ab'; end;
function ElemEq(const a: array of AnsiString): Boolean; begin ElemEq := a[0] = 'ab'; end;
function IsNil(const s: AnsiString): Boolean; begin IsNil := Pointer(s) = nil; end;
function CharEq(c: Char): Boolean; begin CharEq := c = 'a'; end;
var x, y: AnsiString; f1, f2: string[8]; r: TR; arr: array[0..1] of AnsiString;
begin
  x := 'ab'; y := 'ab';
  f1 := 'ab'; f2 := 'ab';
  r.f := 'ab'; r.g := 'ab';
  arr[0] := 'ab'; arr[1] := 'zz';
  WriteLn('EqA  eq ', EqA(x, y),   ' ne ', EqA(x, 'zz'));
  WriteLn('LtA  lt ', LtA(x, 'b'), ' ge ', LtA('b', x));
  WriteLn('EqF  eq ', EqF(f1, f2), ' ne ', EqF(f1, 'zz'));
  WriteLn('LtF  lt ', LtF(f1, 'b'),' ge ', LtF('b', f1));
  WriteLn('Deref   ', DerefEq(@f1, f2), ' ne ', DerefEq(@f1, 'zz'));
  WriteLn('AddrEq  ', AddrEq(f1, f1), ' ne ', AddrEq(f1, f2));
  WriteLn('CallEq  ', CallEq(0),   ' ne ', CallEq(1));
  WriteLn('Concat  ', ConcatEq('a','b'), ' ne ', ConcatEq('z','z'));
  WriteLn('FieldA  ', FieldEqA(r));
  WriteLn('FieldF  ', FieldEqF(r));
  WriteLn('Elem    ', ElemEq(arr));
  WriteLn('IsNil   ', IsNil(x), ' empty ', IsNil(''));
  WriteLn('CharEq  ', CharEq('a'), ' ne ', CharEq('b'));
end.
