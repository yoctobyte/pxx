program test_nil_check_receiver;
{ Site class 2 of feature-a-emitted-nil-checks: the RECEIVER of a method call.

  THE THIRD LINE IS THE POINT. A method on a nil instance that touches no field
  RUNS TO COMPLETION and returns normally — measured before this check, `o :=
  nil; o.Plain` printed `plain` and carried on. Nothing faults, nothing is
  reported, and the program misbehaves later, somewhere else. That is the
  plausible-wrong-value shape, and it is the reason the non-virtual arm is worth
  more than the virtual one, which at least faults on the VMT load at the call.

  Both arms are here because they lower through different paths — AN_VIRTUAL_CALL
  and AN_CALL — so one can regress without the other.

  The receiver is identified from the SIGNATURE (param 0 named `Self`, typed
  tyClass, by value), which is what excludes the three receivers that can never
  be nil: a class method's metaclass, and a record's or a type helper's by-ref
  Self. `TC.Make` below is a class function called on the class, and it must
  keep working — a check keyed on the name alone would have wrapped its
  metaclass too. }
uses SysUtils;

type
  TC = class
    v: Integer;
    procedure Virt; virtual;
    procedure Plain;
    class function Make: TC;
  end;

procedure TC.Virt; begin writeln('virt v=', v); end;
procedure TC.Plain; begin writeln('plain'); end;      { touches no field }
class function TC.Make: TC; begin Result := TC.Create; Result.v := 7; end;

var o: TC;
begin
  o := TC.Make;         { class method on the class — no instance involved }
  o.Virt;
  o.Plain;
  o := nil;
  try
    o.Virt;
    writeln('NOT REACHED (virtual)');
  except
    on E: EAccessViolation do writeln('caught virtual: ', E.Message);
  end;
  try
    o.Plain;
    writeln('NOT REACHED (non-virtual)');
  except
    on E: EAccessViolation do writeln('caught plain: ', E.Message);
  end;
  writeln('still running');
end.
