{ THE ACCEPT SIDE of the settled-name constraint check -- the control, not the
  demonstration. The two _fail tests beside this one prove the check REJECTS;
  only this one can prove it does not reject too much, and over-rejection is
  the failure mode that would break working code silently.

  Every arm below was accepted before the change and must stay accepted:

    TUnconstrained<LongInt>  an UNCONSTRAINED template with a builtin argument.
                             The new arm keys off the constraint flags, so this
                             must take the untouched early exit. If it ever
                             fails, the check is firing on templates that
                             declared no constraint at all.
    TNeedsClass<TFwd>        a FORWARD-declared class, completed further down.
    TNeedsClass<TPlain>      a class declared EARLIER in the same type section.
                             This is the shape the not-declared-yet exit exists
                             to protect: DelphiRewriteGenericUses inserts the
                             alias immediately after the TEMPLATE, so the
                             specialization is parsed AHEAD of TPlain and the
                             name is not in the class table when the check runs.
                             It is also the shape the guard's own comment cites.

    TNeedsClass<LongInt>     where the program declares `LongInt = class`. THE
                             ARM SAMPLED FROM OUTSIDE THE OLD BOUNDARY, and the
                             only one that could have caught the shape of
                             ce4d9004c: the change made a builtin NAME settle a
                             question, so the case that matters is a user type
                             wearing a builtin's name. FindUClass runs before
                             the builtin arm, so this is accepted and must stay
                             accepted. Added 2026-08-31 after the sibling change
                             to BuiltinTypeNameTk regressed on exactly this
                             shape -- there, SizeOf consulted the builtin table
                             FIRST and a user `type Currency = record` answered
                             8 instead of 12. Same widening, opposite ordering,
                             and only one of the two was safe. A control drawn
                             entirely from the population a change is ABOUT
                             cannot detect a change to that population's EDGE.

  A fourth arm, `TNeedsClass<TLater>` over a class declared later with no
  forward, was written and REMOVED: fpc 3.2.2 rejects it outright ("Identifier
  not found"). We accept it, which is the allowed direction and not a defect,
  but a control whose point is "this must keep working" should not be carried
  by a shape the oracle refuses -- it would document a divergence while
  claiming to guard a regression.

  bug-p-generic-constraints-are-checked-before-the-type-section-closes }
program test_generic_constraint_accept_control;
{$mode delphi}
type
  TUnconstrained<T> = class
  end;
  TNeedsClass<T: class> = class
  end;
  { `T: TObject` against the SAME forward stub, and it is the arm that moved:
    the checker used to skip a forward stub entirely, so both this and a
    DEEPER named constraint passed. It now judges the stub as what it is -- a
    class whose ancestry is TObject and which implements nothing yet -- so the
    deeper ones correctly fail (tgenconstraint38/39, and
    test_generic_constraint_forward_stub_fail.pas) and this one must NOT.
    fpc 3.2.2 accepts it. Over-rejection is the failure mode this file exists
    for, and this is the edge the change actually touched. }
  TNeedsTObject<T: TObject> = class
  end;

  TPlain = class
  end;

  TFwd = class;

  { shadows the builtin scalar name deliberately -- see the note above }
  LongInt = class
  end;

  TOkBuiltinUnconstrained = TUnconstrained<Integer>;
  TOkPlain                = TNeedsClass<TPlain>;
  TOkForward              = TNeedsClass<TFwd>;
  TOkShadowedBuiltin      = TNeedsClass<LongInt>;
  TOkForwardTObject       = TNeedsTObject<TFwd>;

  TFwd = class
  end;

var
  a: TOkBuiltinUnconstrained;
  b: TOkPlain;
  c: TOkForward;
  d: TOkShadowedBuiltin;
  e: TOkForwardTObject;
begin
  a := TOkBuiltinUnconstrained.Create;
  b := TOkPlain.Create;
  c := TOkForward.Create;
  d := TOkShadowedBuiltin.Create;
  e := TOkForwardTObject.Create;
  Writeln('accepted 5');
  a.Free; b.Free; c.Free; d.Free; e.Free;
end.
