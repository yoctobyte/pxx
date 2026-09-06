program test_a_parenless_call_to_an_all_defaulted_method_fills_its_defaults_at_every_receiver_shape;
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
{ bug-p-an-interface-dispatched-call-that-omits-a-defaulted-argument-segfaults

  `o.M;` with no parentheses, where every parameter of M carries a default, is
  an ordinary Pascal call and every receiver shape has to fill those defaults.
  Two questions live under one name in the parser and only one of them is the
  one a parenless call needs: CanFillDefaultsFrom asks *the argument list ENDS
  HERE* AND *the rest can default*, so with no parentheses at all CurTok is `;`
  and it answers False for a method whose parameters plainly do have defaults.
  An arm that reached for it got a guard that silently declined; an arm that
  called CheckMethodCallArity alone got a check that ACCEPTS the short call --
  because the missing parameters have defaults -- and then supplied none. The
  call went out with no arguments and the callee read its parameter off
  whatever was in the register.

  ELEVEN RECEIVER SHAPES IN ONE FILE, and the file exists because the defect
  was ONE of them. When it was found, ten of these were already correct: a free
  routine, an instance method, a class method, a metaclass, a record method, a
  selector chain, an implicit Self, a grouped `(o)`, a grouped `(o as T)` and an
  explicit-argument interface call all answered 7, and only `i.M;` through an
  interface reference crashed. **A fixture holding one shape would have been
  green on any nine of the eleven** and the crash would have kept its cover, so
  the shapes are the assertion and not the arrangement.

  The value is asserted, never the fact that it ran: the wrong answer here is
  whatever was in the register, which on a good day is the right number. }
type
  IFoo = interface
    ['{5E1B0A11-1111-4222-8333-444455556666}']
    procedure N(v: Integer = 7);
  end;

  TC = class(TInterfacedObject, IFoo)
    procedure N(v: Integer = 7);
    class procedure CN(v: Integer = 7);
    function Chain: TC;
    procedure Bare;
  end;
  TCClass = class of TC;

  TR = record
    procedure RN(v: Integer = 7);
  end;

var
  fails: Integer;
  got: Integer;

procedure Check(const what: AnsiString);
begin
  if got <> 7 then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want 7');
    fails := fails + 1;
  end;
  got := -1;
end;

procedure FreeN(v: Integer = 7); begin got := v; end;

procedure TC.N(v: Integer = 7); begin got := v; end;
class procedure TC.CN(v: Integer = 7); begin got := v; end;
function TC.Chain: TC; begin Chain := Self; end;
procedure TC.Bare; begin N; end;          { implicit Self, no parentheses }
procedure TR.RN(v: Integer = 7); begin got := v; end;

var
  o: TC;
  r: TR;
  i: IFoo;
  cref: TCClass;
begin
  fails := 0;
  got := -1;
  o := TC.Create;
  i := o;
  cref := TC;

  FreeN;                Check('free routine');
  o.N;                  Check('instance method');
  TC.CN;                Check('class method on the class name');
  cref.CN;              Check('class method through a metaclass');
  r.RN;                 Check('record method');
  o.Chain.N;            Check('method through a selector chain');
  o.Bare;               Check('implicit Self inside a method');
  (o).N;                Check('grouped receiver');
  (o as TC).N;          Check('grouped cast receiver');

  { THE TWO THAT CRASHED, and they are two arms and not one: the plain
    interface reference is built in ParseLValueAST, the parenthesised one in the
    selector walker ~95 lines from where its paren test is read. Fixing the
    first left the second segfaulting, which is why both spellings are here. }
  i.N;                  Check('interface reference');
  (i).N;                Check('grouped interface reference');

  { ...and the explicit-argument spelling of the same call, which was ALWAYS
    right and is the control that made the crash diagnosable: same reference,
    same object, same binary, differing only in whether the argument was
    written. }
  i.N(7);               Check('interface reference, argument written');

  { NO `o.Free` -- `i` holds an interface reference to the same object and
    TInterfacedObject is refcounted, so freeing it by hand is an invalid pointer
    operation (fpc answers RTE 204, measured). The object is released when the
    interface reference goes. That is the oracle's rule, not ours, and the file
    has to obey it to have an oracle at all. }
  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('PARENLESSDEFAULT OK');
end.
