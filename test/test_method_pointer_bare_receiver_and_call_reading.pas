{ TWO HALVES OF ONE DECISION, and before this they lived in three places that
  disagreed: when a method is named with no `@` and no argument list in a context
  that wants a METHOD POINTER, is that a reference or a call?

  HALF ONE -- the RECEIVER. `TryParseParenlessMethodRef` is meant to be the one
  place the reference reading is decided, and it handled two receiver spellings:
  an instance VARIABLE (`s.Pick`) and a class NAME (`TSvc.CPick`). A BARE name
  inside the class's own method (`Pick`, receiver = the implicit Self) fell
  through to the ordinary expression path and was read as a zero-argument CALL:
  `"TSvc.Pick" is a procedure and has no result to use in an expression`. FPC
  accepts it. The bare arm resolves `Self` as the ordinary symbol it is and then
  joins the instance-variable path unchanged, so it is one more spelling of the
  same node, not a fourth construction site.

  HALF TWO -- the CALL READING, which is what makes half one safe to add.
  Delphi's extended-syntax rule is that a bare routine name in a procedural
  context is CALLED when its result fits the target and ADDRESSED when it does
  not. pxx had no such rule here, so on

      function TSvc.Handler: TSel;    { parameterless, RETURNS a method pointer }
      t := Self.Handler;

  it took Handler's ADDRESS, stored a {Code, Data} pair built from the wrong
  routine, compiled clean, and SIGSEGV'd on the first call through `t`. FPC calls
  Handler in both spellings. Measured on `pinned` before the fix, so it is not a
  regression -- it is the same failure shape as
  bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults, one construct
  further on. The rule now lives in MethodResultSatisfiesTarget, INSIDE the
  helper, so all three receiver spellings get it rather than the arm that
  happened to need it.

  WHY THE ASSIGNMENT SITE IS IN THIS TEST AT ALL. The two contexts that want a
  method pointer -- a cast to a method-pointer type, and an assignment whose LHS
  is a method-pointer lvalue -- were answering the question separately: the cast
  asked the helper, the assignment carried its own hand-written copies of the two
  receiver arms. So the bare receiver had to be added twice and the call reading
  fixed twice, which is exactly the shape root-cause-over-microfix.md says to
  stop and count. The assignment site now asks the helper too, which is why every
  row below has both a `t := ...` and a `TSel(...)` form.

  A THIRD AXIS IS STILL OPEN and is deliberately not tested here: the LHS
  spelling. `Result := Self.Pick` inside a function returning a method pointer
  is refused for every receiver spelling, because the implicit `Result` symbol
  is allocated as a plain var with no procedural signature. Locals are used
  throughout below for that reason;
  bug-p-result-is-not-a-method-pointer-lvalue carries it.

  Oracle: FPC 3.2.2 prints the same lines. }
program test_method_pointer_bare_receiver_and_call_reading;

{$MODE DELPHI}

type
  TSel = procedure of object;

  TSvc = class
    N: LongInt;
    procedure Pick;
    { the call-reading subject: parameterless, and its result IS the target type }
    function Handler: TSel;
    { arm A -- bare receiver, in both contexts }
    function BareAssign: TSel;
    function BareCast: TSel;
    { controls -- the two spellings that already worked, in both contexts }
    function SelfAssign: TSel;
    function SelfCast: TSel;
    { the call reading, in both spellings }
    function CallBare: TSel;
    function CallDotted: TSel;
  end;

procedure TSvc.Pick;
begin
  writeln('picked ', N);
end;

function TSvc.Handler: TSel;
var t: TSel;
begin
  writeln('handler-ran');
  { the temp is NOT decoration and NOT a workaround for this test's subject:
    `Result := Self.Pick` is refused for EVERY receiver spelling, because the
    implicit `Result` symbol of a method-pointer-returning function is allocated
    as a plain var with no recorded procedural signature, so the LHS never looks
    like a method-pointer lvalue and the arm that asks the helper never fires.
    That is a third axis -- LHS spellings, not receiver spellings -- and it is
    filed as bug-p-result-is-not-a-method-pointer-lvalue rather than dodged
    silently. Every other assignment below writes to a local for the same
    reason. }
  t := Self.Pick;
  Result := t;
end;

function TSvc.BareAssign: TSel;
var t: TSel;
begin
  t := Pick;
  Result := t;
end;

function TSvc.BareCast: TSel;
var t: TSel;
begin
  t := TSel(Pick);
  Result := t;
end;

function TSvc.SelfAssign: TSel;
var t: TSel;
begin
  t := Self.Pick;
  Result := t;
end;

function TSvc.SelfCast: TSel;
var t: TSel;
begin
  t := TSel(Self.Pick);
  Result := t;
end;

function TSvc.CallBare: TSel;
var t: TSel;
begin
  t := Handler;        { a CALL: Handler's result already is a TSel }
  Result := t;
end;

function TSvc.CallDotted: TSel;
var t: TSel;
begin
  t := Self.Handler;   { the same, dotted }
  Result := t;
end;

var
  s: TSvc;
  f: TSel;
begin
  s := TSvc.Create;
  s.N := 41;

  f := s.BareAssign;  f();
  f := s.BareCast;    f();
  f := s.SelfAssign;  f();
  f := s.SelfCast;    f();

  { each of these must print handler-ran FIRST -- proof it was called and not
    addressed -- and then picked, proof the pointer it returned is usable }
  f := s.CallBare;    f();
  f := s.CallDotted;  f();

  { and the outside-the-class control, which never went through any of this }
  f := s.Pick;        f();
end.
