{ The integer parsers, and the fact that there is now only ONE of them
  (bug-b-strtoint-parsers-disagree).

  This file compiles under FPC and every expectation was read off an FPC build
  of it. It exists in two halves:

  1. FOUR ENTRY POINTS, ONE ANSWER. StrToIntDef / StrToInt64Def / TryStrToInt /
     TryStrToInt64 were four separate implementations that disagreed with each
     other -- TryStrToInt accepted a trailing space StrToIntDef rejected, and
     only some saw a radix prefix. Testing one of them could not have found
     that, so the cross-checks below assert they AGREE, not merely that each is
     right.
  2. THE BOUNDARIES, where a hand-written parser goes wrong quietly: Low(Int64)
     (no positive counterpart), the exact overflow edge, and the difference
     between 32-bit truncation and 64-bit rejection. }
program lib_strtoint;
uses sysutils;

var fails: Integer;

procedure Chk(const what, got, want: string);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=[', got, '] want=[', want, ']'); fails := fails + 1; end;
end;

{ every entry point on one input, rendered as one string so a disagreement
  between them is a single visible failure }
function All(const s: string): string;
var v: Integer; v64: Int64; r: string;
begin
  r := IntToStr(StrToIntDef(s, -999)) + ',';
  if TryStrToInt(s, v) then r := r + IntToStr(v) else r := r + 'X';
  r := r + ',' + IntToStr(StrToInt64Def(s, -999)) + ',';
  if TryStrToInt64(s, v64) then r := r + IntToStr(v64) else r := r + 'X';
  All := r;
end;

begin
  fails := 0;

  { ---- radix prefixes, sign before the prefix ---- }
  Chk('hex-dollar',  IntToStr(StrToIntDef('$FF', -999)),   '255');
  Chk('hex-lower',   IntToStr(StrToIntDef('$ff', -999)),   '255');
  Chk('hex-mixed',   IntToStr(StrToIntDef('$aF', -999)),   '175');
  Chk('hex-0x',      IntToStr(StrToIntDef('0x10', -999)),  '16');
  Chk('hex-0X',      IntToStr(StrToIntDef('0X10', -999)),  '16');
  Chk('octal',       IntToStr(StrToIntDef('&17', -999)),   '15');
  Chk('binary',      IntToStr(StrToIntDef('%1010', -999)), '10');
  Chk('neg-hex',     IntToStr(StrToIntDef('-$FF', -999)),  '-255');
  Chk('space-hex',   IntToStr(StrToIntDef(' $10', -999)),  '16');

  { ---- a digit outside the base is malformed, not a silent stop ---- }
  Chk('octal-bad',   IntToStr(StrToIntDef('&19', -999)),   '-999');
  Chk('binary-bad',  IntToStr(StrToIntDef('%12', -999)),   '-999');
  Chk('prefix-only', IntToStr(StrToIntDef('$', -999)),     '-999');
  Chk('0x-only',     IntToStr(StrToIntDef('0x', -999)),    '-999');
  { '0' is not a prefix unless x/X follows }
  Chk('zero',        IntToStr(StrToIntDef('0', -999)),     '0');
  Chk('lead-zero',   IntToStr(StrToIntDef('09', -999)),    '9');

  { ---- whitespace: leading yes, trailing no ---- }
  Chk('lead-space',  IntToStr(StrToIntDef(' 42', -999)),   '42');
  Chk('trail-space', IntToStr(StrToIntDef('42 ', -999)),   '-999');

  { ---- the boundaries ---- }
  Chk('int64-low',   IntToStr(StrToInt64Def('-9223372036854775808', 0)),
                     '-9223372036854775808');
  Chk('int64-high',  IntToStr(StrToInt64Def('9223372036854775807', 0)),
                     '9223372036854775807');
  { one past each end is rejected, not wrapped -- this returned a wrapped
    value before, which is the silent-wrong-value shape }
  Chk('int64-low-1', IntToStr(StrToInt64Def('-9223372036854775809', -999)), '-999');
  Chk('int64-hi+1',  IntToStr(StrToInt64Def('9223372036854775808', -999)),  '-999');
  Chk('int64-huge',  IntToStr(StrToInt64Def('99999999999999999999999', -999)), '-999');

  { 32-bit TRUNCATES rather than rejecting -- FPC's rule, and the asymmetry
    with the 64-bit case above is deliberate on FPC's part }
  Chk('trunc-32',    IntToStr(StrToIntDef('99999999999', -999)),  '1215752191');
  Chk('trunc-32-b',  IntToStr(StrToIntDef('2147483648', -999)),   '-2147483648');
  Chk('trunc-32-hex',IntToStr(StrToIntDef('$FFFFFFFF', -999)),    '-1');

  { ---- and IntToStr back over the same boundary: negating Low(Int64) leaves
    it unchanged, which used to leave a bare '-' ---- }
  Chk('tostr-low',   IntToStr(Low(Int64)),  '-9223372036854775808');
  Chk('tostr-high',  IntToStr(High(Int64)), '9223372036854775807');
  Chk('tostr-small', IntToStr(-9) + '/' + IntToStr(-10) + '/' + IntToStr(0), '-9/-10/0');

  { ---- ALL FOUR ENTRY POINTS AGREE (the actual root cause) ---- }
  Chk('agree-plain',  All('42'),    '42,42,42,42');
  Chk('agree-hex',    All('$FF'),   '255,255,255,255');
  Chk('agree-trail',  All('42 '),   '-999,X,-999,X');
  Chk('agree-lead',   All(' 42'),   '42,42,42,42');
  Chk('agree-empty',  All(''),      '-999,X,-999,X');
  Chk('agree-junk',   All('42abc'), '-999,X,-999,X');
  Chk('agree-huge',   All('99999999999999999999999'), '-999,X,-999,X');
  Chk('agree-neg',    All('-7'),    '-7,-7,-7,-7');

  if fails = 0 then WriteLn('STRTOINT OK')
  else WriteLn('STRTOINT FAILED ', fails);
end.
