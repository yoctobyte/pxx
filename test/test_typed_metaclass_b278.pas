{ TYPED metaclasses: `TBaseClass = class of TBase`.

  Two gaps this pins, both of which fpcunit's suite builder walks straight into:

  1. ANY constructor through the metaclass, not just one spelled `Create`. FPC names them
     freely -- fpcunit calls `tc.CreateWith(name, sn)` -- and UMthIsCtor is what marks
     one. Matching on the NAME 'create' silently missed every other constructor, which
     then fell through to the member paths and did something else entirely.

  2. A CLASS METHOD through the metaclass (`tc.Tag`). Now that a class method's Self is a
     real argument, this needs no new machinery: pass the metaclass VALUE as Self and the
     method runs against whatever class the variable holds.

  Note `tc.Tag` binds to TBase.Tag even when tc holds TDerived -- Tag is not virtual, so
  FPC binds it by the variable's DECLARED class -- but Self is still TDerived, so it
  prints 'tag of TDerived'. That is FPC's behaviour, not an approximation of it. The
  CONSTRUCTOR is virtual, so it really does build a TDerived.

  x86-64 ONLY, deliberately: constructing through a class reference with ARGUMENTS
  segfaults on every other target, and has done all along -- it reproduces with the old
  `Create` spelling and the old code path. See bug-cross-metaclass-new-with-args. Do not
  add this to a cross list until that is fixed. }
program test_typed_metaclass_b278;
type
  TBase = class
    FName: string;
    constructor CreateWith(const n: string); virtual;
    class function Tag: string;
  end;
  TBaseClass = class of TBase;          { a TYPED metaclass }
  TDerived = class(TBase)
    constructor CreateWith(const n: string); override;
    class function Tag: string;
  end;
constructor TBase.CreateWith(const n: string);
begin FName := 'base:' + n; end;
class function TBase.Tag: string;
begin Result := 'tag of ' + Self.ClassName; end;
constructor TDerived.CreateWith(const n: string);
begin inherited CreateWith(n); FName := 'derived:' + n; end;
class function TDerived.Tag: string;
begin Result := 'D-tag of ' + Self.ClassName; end;
var
  tc: TBaseClass;
  o: TBase;
begin
  tc := TBase;
  o := tc.CreateWith('x');            { non-'Create' ctor through a metaclass }
  writeln('1: ', o.FName, ' | ', tc.Tag);
  tc := TDerived;
  o := tc.CreateWith('y');            { dynamic: must build a TDerived }
  writeln('2: ', o.FName, ' | ', tc.Tag);
  writeln('3: ', o.ClassName);
end.
