program test_generic_mutual_reference;
{$MODE OBJFPC}{$H+}

// Two generics that reference each other, where only ONE direction is a
// declaration-time dependency. FPC prints 7; we used to refuse the whole
// program with `circular generic specialization`.
//
//   TDel<T> inherits TEq<T>          -> declaration time: real, must be ordered
//   TEq<T>'s METHOD BODY names TDel  -> materialisation time: needed when that
//                                       method is streamed, which is later
//
// Treating the second as the first makes each side wait for the other and
// manufactures a cycle out of a program that has none.
// bug-p-mutually-referencing-generics-are-rejected-as-circular
//
// The GENUINE cycle is asserted separately by test_generic_cycle_fail.pas and
// must keep being REFUSED -- these two are a pair, and a change that turns
// this one green by disabling the detector turns that one red.
//
// NOTE: no brace-comments in this file. A '}' inside a { } comment ends the
// comment early in FPC and silently kills the oracle.
type
  generic TEq<T> = class
    class function Make: LongInt;
  end;

  generic TDel<T> = class(specialize TEq<T>)   // declaration-time: inheritance
  end;

class function TEq.Make: LongInt;
var d: specialize TDel<T>;                     // materialisation-time only
begin
  d := nil;
  if d = nil then Result := 7 else Result := 0;
end;

type TE1 = specialize TEq<LongInt>;
begin
  WriteLn(TE1.Make);
end.
