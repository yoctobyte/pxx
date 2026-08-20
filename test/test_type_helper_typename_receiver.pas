program test_type_helper_typename_receiver;
{ feature-pascal-type-helpers v3: the TARGET TYPE'S OWN NAME as the receiver —
  `UInt32.GetSignMask`, which is how generics.helpers spells its UInt32/UInt64
  sections. Before this, the type's name is not a class, so FindUClass missed
  and it was `undefined variable (UInt32)`.

  It is not a second dispatch path: the name resolves to the HELPER's ci, which
  makes it the exact spelling that already worked (`TU32Helper.GetSignMask`), so
  the existing static / class-const block serves it unchanged — including the
  by-value dummy Self a helper needs because it has no metaclass.

  The rows are the spellings that must all reach the same helper: the builtin
  name, a NAMED ALIAS of it (TMyInt = LongWord), an alternative builtin spelling
  of the same type (Cardinal), and a string-typed helper. Row f is the guard
  that matters most — a BARE type name must still be a type, not a class
  reference, so `SizeOf(UInt32)` and an ordinary UInt32 variable are asserted in
  the same program.

  Checked against FPC 3.2.2 (with {$modeswitch typehelpers}): it answers
  2147483648 for `UInt32.GetSignMask`. Note FPC REJECTS the helper-name spelling
  `TU32Helper.GetSignMask` ("class helpers cannot be used as types") which pxx
  accepts — a deliberate dialect laxness, not a parity bug, and out of scope
  here.

  Const ARRAYS through either spelling (`UInt32.SIZED_SIGN_MASK[i]`) are still
  refused, identically through the helper name too, so that is a pre-existing
  typed-const gap and not this feature's — see the ticket. }
type
  TMyInt = LongWord;
  TU32Helper = record helper for UInt32
    const SIGN_BIT = $80000000;
    const NAMEY = 'u32';
    class function GetSignMask: UInt32; static;
  end;
  TStrHelper = type helper for AnsiString
    class function Tag: AnsiString; static;
  end;
class function TU32Helper.GetSignMask: UInt32; begin GetSignMask := SIGN_BIT; end;
class function TStrHelper.Tag: AnsiString; begin Tag := 'str'; end;
var c: UInt32;
begin
  c := 5;
  Writeln('a typename static  : ', UInt32.GetSignMask);
  Writeln('b alias  static    : ', TMyInt.GetSignMask);
  Writeln('c cardinal spelling: ', Cardinal.GetSignMask);
  Writeln('d string typename  : ', AnsiString.Tag);
  Writeln('e typename const   : ', UInt32.SIGN_BIT, ' ', UInt32.NAMEY);
  Writeln('f bare type is type: ', SizeOf(UInt32), ' ', c);
end.
