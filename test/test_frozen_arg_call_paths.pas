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

constructor TB.Create(const a: AnsiString); begin val := a; end;
procedure TB.M(const a: AnsiString); begin WriteLn('M  [', a, ']'); end;
procedure TB.V(const a: AnsiString); begin WriteLn('V  [', a, ']'); end;
procedure TD.V(const a: AnsiString); begin WriteLn('Vd [', a, ']'); end;
procedure P(const a: AnsiString); begin WriteLn('P  [', a, ']'); end;
procedure P2(const a, b: AnsiString); begin WriteLn('P2 [', a, '|', b, ']'); end;

var
  s: string[10];
  o: TB;
  d: TD;
  pv: TPr;

begin
  s := 'plain';
  P(s);                                        { direct call }
  P2(s, s);                                    { two frozen args, ordered path }
  o := TB.Create(s); WriteLn('C  [', o.val, ']');   { constructor }
  o.M(s);                                      { non-virtual method }
  o.V(s);                                      { virtual, base }
  d := TD.Create(s); d.V(s);                   { virtual, overridden }
  pv := @P; pv(s);                             { proc-var indirect }
  P('lit');                                    { the control -- always worked }
end.
