{ A CALL THROUGH A METHOD POINTER, in the shapes that differ in the IR.

  A `procedure(x: Integer) of object` value is a {Code, Data} pair, and the
  call prepends Self to the argument chain WITHOUT the signature proc growing
  a parameter -- ir.inc records the count on the node (`IRC = extra leading
  Self args`). A register backend never has to read that: it pushes Self and
  calls. A backend whose call sites are CHECKED against a type does, and
  wasm32 did not, so every one of these rows refused to lower there while
  every register target was green. That asymmetry is why this is a cross test
  and not a native one.

  Deliberately no SizeOf row: a method pointer is two POINTERS, so its size is
  16 on a 64-bit target and 8 on a 32-bit one. Comparing a 32-bit target's
  output against the x86-64 build's would fail on a correct answer. The rows
  below are all VALUES, which every target must agree on.

  Rows, each a different lowering:
    - zero declared parameters      (the signature is Self alone)
    - one and two declared          (the ordinary shape)
    - a FUNCTION result             (an operand left on the stack)
    - a `var` parameter             (an address, not a value, after Self)
    - a VIRTUAL method              (the pointer must reach the override)
    - a RECORD result               (hidden destination AND Self together --
                                     one trailing operand and one leading one,
                                     and a backend that got the order wrong
                                     would still push the right count)
    - through a record FIELD and through a plain VARIABLE

  The parameterless rows are written `h.nul()` rather than `h.nul` because a
  procedural value reached through anything but a BARE IDENTIFIER is rejected
  when called with no argument list -- `h.p;`, `h.nul;` and `a[0];` all give
  `expected ':=' before ';'` while `m;` compiles. That is a frontend gap, not
  a codegen one, and it is filed rather than worked around silently:
  bug-p-a-parameterless-procedural-value-is-only-callable-bare-as-an-identifier
    - reassigned to a second object (Self is the value, not the code) }
program test_cross_method_pointer_call;

type
  TPair = record u, v: LongInt; end;

  TBase = class
    tag: LongInt;
    constructor Create(t: LongInt);
    procedure Nul;
    procedure One(x: LongInt);
    procedure Two(x, y: LongInt);
    function  Fn(x: LongInt): LongInt;
    procedure Outp(var x: LongInt);
    function  Rec(x: LongInt): TPair;
    procedure Speak; virtual;
  end;

  TDer = class(TBase)
    procedure Speak; override;
  end;

  THolder = record
    nul:  procedure of object;
    one:  procedure(x: LongInt) of object;
    fn:   function(x: LongInt): LongInt of object;
    outp: procedure(var x: LongInt) of object;
    rec:  function(x: LongInt): TPair of object;
    spk:  procedure of object;
    n:    LongInt;
  end;

constructor TBase.Create(t: LongInt); begin tag := t; end;
procedure TBase.Nul;                  begin WriteLn('nul  tag=', tag); end;
procedure TBase.One(x: LongInt);      begin WriteLn('one  tag=', tag, ' x=', x); end;
procedure TBase.Two(x, y: LongInt);   begin WriteLn('two  tag=', tag, ' ', x, ' ', y); end;
function  TBase.Fn(x: LongInt): LongInt; begin Fn := tag * 100 + x; end;
procedure TBase.Outp(var x: LongInt); begin x := x + tag; end;
function  TBase.Rec(x: LongInt): TPair;
begin Rec.u := tag + x; Rec.v := tag - x; end;
procedure TBase.Speak;                begin WriteLn('speak base tag=', tag); end;
procedure TDer.Speak;                 begin WriteLn('speak DER  tag=', tag); end;

var
  b, b2: TBase;
  d: TDer;
  h: THolder;
  two: procedure(x, y: LongInt) of object;   { a plain variable, not a field }
  k: LongInt;
  pr: TPair;
begin
  b  := TBase.Create(1);
  b2 := TBase.Create(7);
  d  := TDer.Create(9);

  h.n := 42;
  h.nul  := @b.Nul;
  h.one  := @b.One;
  h.fn   := @b.Fn;
  h.outp := @b.Outp;
  h.rec  := @b.Rec;
  h.spk  := @d.Speak;

  h.nul();
  h.one(5);
  WriteLn('fn   ', h.fn(5));

  k := 10; h.outp(k);
  WriteLn('outp ', k, '   (must be 11)');

  pr := h.rec(4);
  WriteLn('rec  ', pr.u, ' ', pr.v, '   (must be 5 -3)');

  h.spk();                     { a method pointer onto a VIRTUAL method }

  two := @b.Two;  two(2, 3);
  two := @b2.Two; two(2, 3);   { same code, different Self }

  WriteLn('after ', h.n, '   (must be 42)');

  b.Free; b2.Free; d.Free;
end.
