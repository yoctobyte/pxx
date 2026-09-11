{ The interface half of the cycle, for
  test_p_a_unit_after_the_cycle_closer_in_one_clause.pas.

  Same shape as ucycle_a and for the same reason: the declarations sit BELOW
  this unit's own `uses`, so ucyctail_b asks for them at a moment when this
  interface has been read only as far as that line.
  bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface }
unit ucyctail_a;
interface
uses ucyctail_b;                  { <- the interface half of the cycle }

const
  TAILCONST = 41;

type
  TTailRec = record
    Tag: LongInt;
  end;

implementation

end.
