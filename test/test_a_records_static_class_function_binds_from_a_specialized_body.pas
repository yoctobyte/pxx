{ A RECORD's `class function ...; static;` must be one proc, not two.

  The declaration inside the record and the out-of-line implementation each
  register Self, and they disagreed: the decl side had no static arm and typed
  Self as the RECORD BY REFERENCE, while the impl side's `isStaticMethod` arm
  types it as the bare class reference. FindProcOverloadRec could not match
  them, so the implementation minted a SECOND proc row instead of filling the
  declaration's.

  WHY A GENERIC CALLER IS LOAD-BEARING: with an ordinary caller the call is
  parsed AFTER the implementation and binds to the row that has the body, so the
  bodyless row is simply never called and nothing is observable. A specialized
  body is materialised EARLY -- before a later implementation is parsed -- so it
  binds to the declaration's row, and the failure arrives at LINK time as
  `unresolved forward: TInst.Mk`, naming compiler/builtin/builtinheap.pas. This
  file does not produce a wrong number without the fix; it does not compile.

  The VALUES are the second assertion, and they are what says the two rows were
  merged onto the right shape: registering the decl's record-by-reference Self
  and letting the impl fill THAT row also gives one proc, and every call then
  segfaults -- a static call site has no instance to pass.
  bug-p-a-records-static-class-function-has-no-body-when-the-call-is-in-a-specialized-body }
program test_a_records_static_class_function_binds_from_a_specialized_body;
{$mode delphi}
type
  TFlat = record
    V: LongInt;
    class function Mk(A: LongInt): TFlat; static;
  end;

  TOwner = class
  public type
    TInner = record
      V: LongInt;
      class function Mk(A: LongInt): TOwner.TInner; static;
    end;
  end;

  TMaker<T> = class(TOwner)
    class function Flat(A: LongInt): TFlat; static;
    class function Inner(A: LongInt): TOwner.TInner; static;
  end;

class function TFlat.Mk(A: LongInt): TFlat;
begin
  Result.V := A + 1;
end;

class function TOwner.TInner.Mk(A: LongInt): TOwner.TInner;
begin
  Result.V := A + 2;
end;

class function TMaker<T>.Flat(A: LongInt): TFlat;
begin
  Result := TFlat.Mk(A);
end;

class function TMaker<T>.Inner(A: LongInt): TOwner.TInner;
begin
  Result := TInner.Mk(A);
end;

var
  f: TFlat;
  n: TOwner.TInner;
begin
  f := TMaker<LongInt>.Flat(10);
  n := TMaker<LongInt>.Inner(20);
  WriteLn('flat  ', f.V);
  WriteLn('inner ', n.V);
  { and the ordinary, non-specialized caller keeps working }
  f := TFlat.Mk(100);
  WriteLn('plain ', f.V);
end.
