program test_own_lang_first_pascal_shadow;
{ The boundary on the other side: a PASCAL unit redefining an intrinsic
  spelling must still shadow it. Own-language-first applies to CROSS-language
  collisions only, and FPC prints 77.0000 here too — see olf_pshadow.pas.

  Without this control, "make the intrinsic win" is an easy and wrong way to
  make the other two tests pass. feature-a-own-language-first-symbol-resolution }
uses math, olf_pshadow;
begin
  WriteLn('Exp=', Exp(1.0):0:4);
end.
