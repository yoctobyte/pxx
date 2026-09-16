unit prepasserr_base;
{ The type the directive in prepasserr_mid asks the width of. It lives ONE UNIT
  FURTHER than the directive on purpose -- that extra hop is the entire variable.
  With this declaration moved into prepasserr_mid the same ladder answers
  correctly, measured, so a two-unit fixture would pass on the unfixed
  compiler. }
interface
type tprepasswidechar = word;
implementation
end.
