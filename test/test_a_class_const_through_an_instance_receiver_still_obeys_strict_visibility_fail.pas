program test_a_class_const_through_an_instance_receiver_still_obeys_strict_visibility_fail;
{ bug-p-a-class-const-is-unreachable-through-an-instance-receiver

  The guard on the fix, and it exists because the fix ADDED a way in.
  ClassConstThroughReceiver is a new route to a class const, and a new route to
  a member is a new route past whatever guards the old one. It calls
  EnforceMemberVis for exactly that reason, and this file is the only thing
  that reads that call.

  ONE illegal access, and it is deliberately the ONLY one. test_class_const_
  visibility_strict_fail.pas already covers a strict-private const reached from
  a DESCENDANT METHOD, and adding the instance row there would have been
  cheaper and worthless: that file would keep failing on its own row if the
  visibility call in the new helper were ever dropped, so it cannot see this.
  A guard that another row can satisfy is not a guard.

  Two runs, both asserted in the Makefile:
    lax (the default dialect)  -- MUST COMPILE. Before the fix it did not: the
      instance spelling answered `"Secret": no such member on this record/class`
      and never reached a visibility question at all. So the lax run is also
      the positive control that the new route exists.
    --strict-visibility        -- MUST BE REFUSED, with the SAME message the
      qualified spelling `TB.Secret` gets. `strict private` is TYPE-scoped, so
      the program body is outside it even though the class is declared here.

  The two runs together are the claim: the instance receiver reaches exactly
  what the type-name receiver reaches, and refuses exactly what it refuses. }

type
  TB = class
  strict private const Secret = 5;
  end;

var
  b: TB;
begin
  b := TB.Create;
  WriteLn(b.Secret);   { strict private, and the program body is not TB }
end.
