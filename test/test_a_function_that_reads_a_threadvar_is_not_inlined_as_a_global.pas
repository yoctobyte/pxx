program test_a_function_that_reads_a_threadvar_is_not_inlined_as_a_global;
{ bug-a-a-threadvar-in-a-units-implementation-section-silently-reads-zero.

  THE TICKET'S TITLE IS WRONG AND THIS FIXTURE IS NAMED FOR THE CAUSE INSTEAD.
  The unit's implementation section was never the variable: what decides the
  outcome is whether the routine that reads the threadvar is a FUNCTION the
  -O2 inliner retains. A threadvar symbol is `skGlobal` and at retention time
  its reference is still a plain AN_IDENT -- ThreadVarRewriteRange runs at
  CompileAST, which is AFTER TryRetainInlineBody -- so InlineExprSimple's
  global arm accepted it and CloneToInlineRegion copied a PLAIN GLOBAL read
  into the permanent inline region. PXXDBG=a.inline said so in one word:
  `RETAIN F shape=1 params=0 readsGlobal`.

  TWO SYMPTOMS, ONE CAUSE, and that is why this file carries both. A body
  retained BEFORE the first rewrite was then swept by it -- the sweep started
  at node 0, which is inside the inline reserve -- and its address node came
  from AllocNode, i.e. the VOLATILE region, which is rolled back per statement
  and recycled: the call site read a stale node and SEGFAULTED. A body retained
  AFTER that first sweep was never swept at all -- the watermark had moved past
  the reserve for good -- and read the threadvar's unused BSS slot, i.e. ZERO,
  silently. Every row below fails one way or the other on the unfixed compiler
  and none of them fails on the pin for the reason the ticket first gave.

  ORDINARY -O: no flag. The default is -O2 and that is where it breaks; at -O0
  and -O1 nothing is retained and every row below was already correct. A
  fixture that pinned -O0 would have printed a clean pass through the whole
  defect.

  THE LAST FOUR ROWS ARE THE CONTROL and they must keep their values: the same
  shapes over an ordinary global, which the inliner still retains and must go
  on retaining. If the guard ever widens from "is this a threadvar" to "is this
  a global", those rows stay correct and only a benchmark notices -- so they
  are here to say what was NOT given up, not to catch a wrong value. }

uses utvinline;

threadvar
  mine: LongInt;

var
  plain: LongInt;

function ReadsThreadVar: LongInt;
begin
  Result := mine;
end;

function ReadsThreadVarPlus(n: LongInt): LongInt;
begin
  Result := mine + n;
end;

function ReadsGlobal: LongInt;
begin
  Result := plain;
end;

function ReadsGlobalPlus(n: LongInt): LongInt;
begin
  Result := plain + n;
end;

var
  v: LongInt;

begin
  mine  := 11;
  plain := 100;

  { 1. assigned to a variable first -- this shape SEGFAULTED }
  v := ReadsThreadVar;
  WriteLn('assigned=', v);

  { 2. called inside the WriteLn argument list -- this shape printed its own
       literal twice and then died }
  WriteLn('inline-arg=', ReadsThreadVar);

  { 3. in an expression, and with a parameter beside the threadvar }
  v := ReadsThreadVar + 1;
  WriteLn('expression=', v);
  WriteLn('with-param=', ReadsThreadVarPlus(4));

  { 4. in a condition }
  if ReadsThreadVar = 11 then WriteLn('condition=ok') else WriteLn('condition=WRONG');

  { 5. the unit, both sections. Bump writes the implementation-section
       threadvar; the function and the procedure read the same storage. }
  Bump;
  WriteLn('unit-impl-function=', GotViaFunction);
  v := -1;
  GotViaProcedure(v);
  WriteLn('unit-impl-procedure=', v);

  ifcCounter := 5;
  WriteLn('unit-intf-function=', GotIfc);

  { 6. the control: the same shapes over an ordinary global }
  v := ReadsGlobal;
  WriteLn('global-assigned=', v);
  WriteLn('global-inline-arg=', ReadsGlobal);
  WriteLn('global-expression=', ReadsGlobal + 1);
  WriteLn('global-with-param=', ReadsGlobalPlus(4));
end.
