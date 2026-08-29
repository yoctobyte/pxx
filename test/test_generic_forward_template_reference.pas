program test_generic_forward_template_reference;
{$MODE DELPHI}{$H+}

// A template's method body naming a template declared LATER in the same type
// section. FPC accepts BOTH orderings; we accepted only one, and gave
// `undefined variable (specialize)` for this one -- a 14-line program whose
// only difference from a compiling one is the order of two declarations.
//
// In mode Delphi the rewrite emits a template's alias right behind THAT
// template's own declaration, so the class is specialized before TDeriv is
// declared -- and until it is, `TDeriv<T>` here has not been rewritten to
// `specialize TDeriv<T>`, so no scan can find it (the trace shows nested=0).
// The prerequisite is emitted at the END of the type section instead, where it
// is parsed before the method impls that need it.
// bug-p-a-generic-specialized-before-its-declaration-is-unresolvable
// bug-p-a-generic-prerequisite-is-emitted-before-the-referenced-template-exists
//
// NOTE: no brace-comments in this file -- a '}' inside a { } comment ends the
// comment early in FPC and silently kills the oracle.

type
  TBase<T> = class
    class function Ordinal: TObject;
  end;
  TDeriv<T> = class            // declared AFTER the class whose body names it
  end;

class function TBase<T>.Ordinal: TObject;
begin
  Result := TDeriv<T>.Create;
end;

// the reverse order must keep working -- it is the arm that always compiled
type
  TEarly<T> = class
  end;
  TLate<T> = class
    class function Get: TObject;
  end;

class function TLate<T>.Get: TObject;
begin
  Result := TEarly<T>.Create;
end;

type
  TInst  = TBase<UnicodeString>;
  TInst2 = TLate<LongInt>;
begin
  WriteLn('fwd ', Assigned(TInst.Ordinal));
  WriteLn('back ', Assigned(TInst2.Get));
end.
