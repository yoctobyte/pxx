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

  TPlain = class
  end;

  TFwd = class;

  TOkBuiltinUnconstrained = TUnconstrained<LongInt>;
  TOkPlain                = TNeedsClass<TPlain>;
  TOkForward              = TNeedsClass<TFwd>;

  TFwd = class
  end;

var
  a: TOkBuiltinUnconstrained;
  b: TOkPlain;
  c: TOkForward;
begin
  a := TOkBuiltinUnconstrained.Create;
  b := TOkPlain.Create;
  c := TOkForward.Create;
  Writeln('accepted 3');
  a.Free; b.Free; c.Free;
end.
