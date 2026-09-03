program test_frozen_arg_call_paths;

{ A frozen `string[N]` handed to a MANAGED (AnsiString) parameter, through
  EVERY CALL PATH the backends emit separately.

  Before the conversion moved into IRLowerCallArg, each backend carried this
  marshalling once per call path -- ordered args, direct call, constructor,
  method/vmt, proc-var indirect -- roughly fifteen copies of one decision, and
  four were right. The constructor and virtual rows arrived EMPTY on i386,
  arm32, aarch64 and riscv32, and the proc-var row arrived empty on x86-64 too.
  In the DEFAULT mode, reproducing at the pin.

  bug-a-a-frozen-string-argument-is-empty-through-a-constructor-or-a-virtual-call-on-every-cross-backend

  WHY THE ARGUMENT IS A VARIABLE AND THE LITERAL ROW IS SEPARATE. A string
  LITERAL was correct through every path on every target while all of the above
  was broken -- every backend has a static-handle fast path for it -- so a suite
  whose arguments are literals passes against the bug fully present. That is
  why the class tests never saw this. The literal row is kept as the CONTROL
  that must stay correct, never as coverage.

  THE NON-VARIABLE ARGUMENT SPELLINGS (frankB). A record FIELD, an array
  ELEMENT and a function RESULT typed `string[N]` were all REFUSED by overload
  resolution against an AnsiString parameter until
  bug-a-a-frozen-record-field-is-refused-by-overload-resolution-against-an-ansistring-parameter,
  so they could not be rows here when this file was written. They are separate
  shapes, not spellings of the variable row: a field carries its kind on ASTTk,
  an element on the ARRAY symbol, and a call result on Procs[].RetType -- three
  entities, and the width has to be asked of each. The array element was the
  one that stayed wrong after the refusal lifted: with no arm for it, no width
  mismatch was seen against a frozen formal and no copy was emitted, so a
  1-byte-prefixed element reached a callee reading an 8-byte prefix. They are
  routed through the CONSTRUCTOR and VIRTUAL paths specifically, because that
  is where the empties lived.

  A FUNCTION RESULT IS ALSO THE ROW THAT WAS BROKEN WITH NO FLAG AT ALL: `P(Mk)`
  was refused in the DEFAULT mode, at the pin, on every target.

  THE VALUE ROWS CANNOT SEE THE OTHER HALF OF THIS FIX. The inline conversions
  allocated a fresh handle per call and nothing owned it: measured on the
  pre-fix compiler, 3000 calls gave allocs=3000 frees=0. Every one of those
  calls printed the right answer on x86-64. tools/assert_no_leak.sh is what sees
  it; see the wiring beside this file. }

type
  TB = class
    val: AnsiString;
    constructor Create(const a: AnsiString);
    procedure M(const a: AnsiString);
    procedure V(const a: AnsiString); virtual;
  end;
  TD = class(TB)
    procedure V(const a: AnsiString); override;
  end;
  TPr = procedure(const a: AnsiString);
  R = record f: string[10]; end;
  TArr = array[0..2] of string[10];

constructor TB.Create(const a: AnsiString); begin val := a; end;
procedure TB.M(const a: AnsiString); begin WriteLn('M  [', a, ']'); end;
procedure TB.V(const a: AnsiString); begin WriteLn('V  [', a, ']'); end;
procedure TD.V(const a: AnsiString); begin WriteLn('Vd [', a, ']'); end;
procedure P(const a: AnsiString); begin WriteLn('P  [', a, ']'); end;
procedure P2(const a, b: AnsiString); begin WriteLn('P2 [', a, '|', b, ']'); end;
function Mk: string[10]; begin Mk := 'ret'; end;

var
  s: string[10];
  o: TB;
  d: TD;
  pv: TPr;
  r: R;
  arr: TArr;

begin
  s := 'plain';
  P(s);                                        { direct call }
  P2(s, s);                                    { two frozen args, ordered path }
  o := TB.Create(s); WriteLn('C  [', o.val, ']');   { constructor }
  o.M(s);                                      { non-virtual method }
  o.V(s);                                      { virtual, base }
  d := TD.Create(s); d.V(s);                   { virtual, overridden }
  pv := @P; pv(s);                             { proc-var indirect }

  { the three non-variable spellings, through the paths that were empty }
  r.f := 'field'; arr[1] := 'elem';
  P(Mk);                                       { function result, direct }
  o := TB.Create(Mk); WriteLn('C  [', o.val, ']');   { function result, ctor }
  d.V(Mk);                                     { function result, virtual }
  P(r.f);                                      { record field, direct }
  o := TB.Create(r.f); WriteLn('C  [', o.val, ']'); { record field, ctor }
  d.V(r.f);                                    { record field, virtual }
  P(arr[1]);                                   { array element, direct }
  o := TB.Create(arr[1]); WriteLn('C  [', o.val, ']'); { array element, ctor }
  d.V(arr[1]);                                 { array element, virtual }

  P('lit');                                    { the control -- always worked }
end.
