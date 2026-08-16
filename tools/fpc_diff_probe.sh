#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Differential probe: run small Pascal programs under the pinned pxx stable AND
# FPC, diff their stdout, and report divergences. A cheap way to surface
# FPC-parity bugs (this harness found bug-writeln-boolean-format,
# bug-writeln-real-format, bug-length-rejects-non-variable).
#
# Output: one DIFF line per divergence, in three flavours, because "we differ
# from FPC" is three different facts and collapsing them is what breaks this
# tool:
#
#   DIFF             a NEW divergence -- the only thing that should need action
#   DIFF [known]     a filed bug we have not fixed yet; it will one day go away
#   DIFF [by design] a DELIBERATE dialect decision; it will never go away, and
#                    the reason is printed on the line
#
# The third tag exists because tagging a permanent decision `known` is a lie
# with a cost: `known` promises the row is temporary, so the list is read as a
# backlog. A row that can never leave it makes the count meaningless in the
# other direction — see bug-t-fpc-probe-reports-the-deliberate-shl-deviation-as-new,
# where the deviation instead went UNtagged and pinned `new divergences` at a
# permanent 1, training the reader to skim the one line that must mean
# something.
#
# A pxx compile failure on code FPC accepts is itself a divergence (often a
# missing intrinsic or an "expects a variable" gap) and is reported.
#
# Usage: tools/fpc_diff_probe.sh
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
S="${PXX_STABLE:-"$ROOT/stable_linux_amd64/default/pinned"}"
command -v fpc >/dev/null || { echo "fpc not found"; exit 2; }

new=0
known=0
bydesign=0
skipped=0

# Make invisible bytes visible. Applied to both sides of every reported
# divergence so a whitespace-only difference cannot masquerade as agreement.
# NOTE the separator, not terminator: $( ) has already stripped trailing
# newlines from both sides, so emitting <LF> after the last line would show a
# byte that is not being compared.
vis() { sed -e 's/\r/<CR>/g' -e 's/\t/<TAB>/g' | awk 'NR>1{printf "<LF>"}{printf "%s", $0}'; }

# probe NAME [known | bydesign "<why>"] -- full program on stdin
#
# `bydesign` REQUIRES a reason and refuses without one. The reason is the whole
# point: a permanent deviation has to carry the decision that made it permanent,
# or the next reader has no way to tell it from a bug someone forgot to file.
probe() {
  local name="$1"; local tag="" why=""
  case "${2:-}" in
    known)    tag="known" ;;
    bydesign) tag="bydesign"; why="${3:-}"
              [ -n "$why" ] || { echo "probe $name: bydesign needs a reason" >&2; exit 2; } ;;
  esac
  { echo 'program fdp;'; cat; } > /tmp/fdp.pas   # pxx requires a program header; FPC tolerates either
  local fr pr
  if fpc -Mobjfpc -vw -o/tmp/fdp_f /tmp/fdp.pas >/dev/null 2>&1; then
    fr="$(/tmp/fdp_f 2>&1)"
  else fr="<fpc-compile-fail>"; fi
  if "$S" /tmp/fdp.pas /tmp/fdp_p >/tmp/fdp_c.log 2>&1; then
    pr="$(/tmp/fdp_p 2>&1)"
  else pr="<pxx-compile-fail: $(grep -oE 'error[^(]*' /tmp/fdp_c.log | head -1)>"; fi
  # The oracle check comes FIRST. A case FPC cannot build compared nothing, and
  # returning quietly is how such a case sits in this file for months looking
  # like coverage — one missing `uses` is enough to disarm it, which is exactly
  # what had happened to exc-finally and exc-nested. Say so out loud instead.
  if [ "$fr" = "<fpc-compile-fail>" ]; then
    printf 'SKIP        %-22s no oracle: fpc cannot compile it, so this case proves nothing\n' "$name"
    skipped=$((skipped+1)); return
  fi
  if [ "$fr" = "$pr" ]; then return; fi
  # Render control characters, or a divergence that is PURELY whitespace prints
  # as two identical-looking strings and reads as harness noise. That is exactly
  # how sl-text reported the CRLF-vs-LF bug: fpc=[p\nq] pxx=[p\nq].
  local frv prv
  frv="$(printf '%s' "$fr" | vis)"; prv="$(printf '%s' "$pr" | vis)"
  if [ "$tag" = "known" ]; then
    printf 'DIFF [known] %-22s fpc=[%s] pxx=[%s]\n' "$name" "$frv" "$prv"; known=$((known+1))
  elif [ "$tag" = "bydesign" ]; then
    printf 'DIFF [by design] %-22s fpc=[%s] pxx=[%s]\n           ^ %s\n' \
           "$name" "$frv" "$prv" "$why"; bydesign=$((bydesign+1))
  else
    printf 'DIFF        %-22s fpc=[%s] pxx=[%s]\n' "$name" "$frv" "$prv"; new=$((new+1))
  fi
}

# ---- arithmetic ----
probe int-negdiv   <<'P'
begin writeln((-7) div 2, '|', (-7) mod 2); end.
P
probe int-shr      <<'P'
begin writeln(1 shl 10, '|', 1024 shr 3); end.
P
probe neg-mod      <<'P'
begin writeln(7 mod (-3), '|', (-7) mod (-3)); end.
P
probe div-large    <<'P'
var a, b: int64; begin a := 1000000; b := 1000000; writeln(a * b); end.
P
probe word-wrap    <<'P'
var w: word; begin w := 65535; w := w + 1; writeln(w); end.
P

# ---- ordinals / chars ----
probe char-ord     <<'P'
begin writeln(ord('A'), '|', chr(66)); end.
P
probe inc-dec      <<'P'
var i: integer; begin i := 5; inc(i, 3); dec(i); writeln(i); end.
P

# ---- strings ----
probe str-copy     <<'P'
var s: string; begin s := 'abcdef'; writeln(copy(s, 2, 3)); end.
P
probe str-cmp      <<'P'
begin if 'abc' < 'abd' then writeln('lt') else writeln('ge'); end.
P
probe str-concat   <<'P'
var s: string; begin s := 'a'; s := s + 'b' + 'c'; writeln(s); end.
P
probe str-len-var  <<'P'
var s: string; begin s := 'hello'; writeln(length(s)); end.
P

# ---- sets ----
probe set-in       <<'P'
begin if 3 in [1, 3, 5] then writeln('y') else writeln('n'); end.
P
probe char-set     <<'P'
var c: char; begin c := 'm'; if c in ['a'..'z'] then writeln('low') else writeln('hi'); end.
P

# ---- formatting ----
probe real-fixed   <<'P'
begin writeln(1.5:0:2, '|', (-2.25):0:3); end.
P
probe trunc-round  <<'P'
begin writeln(trunc(3.7), '|', round(2.5), '|', round(3.5)); end.
P

# ---- correctness guards (value semantics; must keep matching FPC) ----
probe rec-copy <<'P'
type tr = record x: integer; end; var a, b: tr; begin a.x := 5; b := a; b.x := 9; writeln(a.x, '|', b.x); end.
P
probe arr-copy <<'P'
type ta = array[0..2] of integer; var a, b: ta; begin a[0] := 5; b := a; b[0] := 9; writeln(a[0], '|', b[0]); end.
P
probe copy-overrun <<'P'
var s: string; begin s := 'abc'; writeln('[' + copy(s, 2, 100) + ']'); end.
P
probe copy-past-end <<'P'
var s: string; begin s := 'abc'; writeln('[' + copy(s, 5, 2) + ']'); end.
P
probe int-div-neg <<'P'
begin writeln((-10) div 3, '|', 10 div (-3)); end.
P
probe mod-signs <<'P'
begin writeln(17 mod 5, '|', (-17) mod 5, '|', 17 mod (-5)); end.
P
probe round-half-neg <<'P'
begin writeln(trunc(-3.7), '|', round(-2.5)); end.
P
probe array-zero-init <<'P'
var a: array[0..3] of integer; begin writeln(a[0], a[1], a[2], a[3]); end.
P
probe concat-loop <<'P'
var s: string; i: integer; begin s := ''; for i := 1 to 5 do s := s + 'x'; writeln(s, '|', length(s)); end.
P

# ---- known/filed divergences (kept as regression markers) ----
probe bool-write known <<'P'
begin writeln(1 > 0, '|', 2 < 1); end.
P
probe real-default known <<'P'
begin writeln(3.14159); end.
P
probe length-literal known <<'P'
begin writeln(length('hello')); end.
P
probe nested-proc known <<'P'
procedure outer; procedure inner; begin writeln('in'); end; begin inner; end;
begin outer; end.
P
probe nested-fn known <<'P'
function f(n: integer): integer; function g(m: integer): integer; begin g := m * 2; end;
begin f := g(n) + 1; end;
begin writeln(f(5)); end.
P
probe low-array known <<'P'
var a: array[5..9] of integer; begin writeln(low(a)); end.
P
probe high-nonzero-array known <<'P'
var a: array[5..9] of integer; begin writeln(high(a)); end.
P
probe builtin-case known <<'P'
var s: string; begin s := 'hi'; writeln(LENGTH(s)); end.
P
probe overload-by-type known <<'P'
function f(a: integer): string; begin f := 'INT'; end;
function f(a: string): string; begin f := 'STR'; end;
begin writeln(f(1), '|', f('x')); end.
P
probe variant-record known <<'P'
type tr = record case boolean of true: (i: integer); false: (c: char); end;
var r: tr; begin r.i := 65; writeln(ord(r.c)); end.
P
probe default-param known <<'P'
function f(a: integer; b: integer = 10): integer; begin f := a + b; end;
begin writeln(f(5), '|', f(5, 1)); end.
P
probe binary-literal known <<'P'
begin writeln(%1010); end.
P
probe as-inline-call known <<'P'
type ta = class end; tb = class(ta) procedure m; end;
procedure tb.m; begin writeln('M'); end;
var o: ta; begin o := tb.create; (o as tb).m; end.
P
probe subrange-type known <<'P'
type tr = 1..10; var x: tr; begin x := 5; writeln(x); end.
P
probe cardinal-sub known <<'P'
var a, b: cardinal; begin a := 3; b := 5; writeln(a - b); end.
P
probe enum-explicit known <<'P'
type te = (a = 1, b = 5, c = 10); begin writeln(ord(a), '|', ord(b), '|', ord(c)); end.
P

# ---- sysutils: conversions ----
probe su-inttostr    <<'P'
uses sysutils; begin writeln(IntToStr(0),'|',IntToStr(-42),'|',IntToStr(2147483647)); end.
P
probe su-strtoint    <<'P'
uses sysutils; begin writeln(StrToInt('42'),'|',StrToInt('-7'),'|',StrToIntDef('zz',9)); end.
P
probe su-inttohex    <<'P'
uses sysutils; begin writeln(IntToHex(255,2),'|',IntToHex(255,4),'|',IntToHex(0,1)); end.
P
probe su-upperlower  <<'P'
uses sysutils; begin writeln(UpperCase('aBc1!'),'|',LowerCase('AbC1!')); end.
P
probe su-trim        <<'P'
uses sysutils; begin writeln('[',Trim('  ab  '),']|[',TrimLeft('  ab'),']|[',TrimRight('ab  '),']'); end.
P
probe su-pos         <<'P'
uses sysutils; begin writeln(Pos('b','abc'),'|',Pos('z','abc'),'|',Pos('','abc')); end.
P
probe su-stringreplace <<'P'
uses sysutils; begin writeln(StringReplace('a.b.c','.','-',[rfReplaceAll]),'|',StringReplace('a.b.c','.','-',[])); end.
P
probe su-format-d    <<'P'
uses sysutils; begin writeln(Format('%d|%5d|%-5d|%05d',[42,42,42,42])); end.
P
probe su-format-s    <<'P'
uses sysutils; begin writeln(Format('%s|%8s|%-8s|%.2s',['ab','ab','ab','abcd'])); end.
P
probe su-format-x    <<'P'
uses sysutils; begin writeln(Format('%x|%X|%8.4x',[255,255,255])); end.
P
# ---- strings ----
probe str-index      <<'P'
var s: string; begin s := 'abc'; writeln(s[1],s[3],'|',Length(s)); end.
P
probe str-setlength  <<'P'
var s: string; begin s := 'abcdef'; SetLength(s,3); writeln('[',s,']',Length(s)); end.
P
probe str-insert-del <<'P'
var s: string; begin s := 'abcd'; Insert('XY',s,2); writeln(s); Delete(s,2,2); writeln(s); end.
P
probe str-compare    <<'P'
begin writeln('a'<'b','|','abc'='abc','|','ab'<'abc'); end.
P
# ---- dynamic arrays ----
probe dyn-setlength  <<'P'
var a: array of Integer; i: Integer;
begin SetLength(a,3); for i:=0 to 2 do a[i]:=i*i; writeln(Length(a),'|',a[0],a[1],a[2],'|',High(a)); end.
P
probe dyn-grow       <<'P'
var a: array of Integer; begin SetLength(a,2); a[0]:=1; a[1]:=2; SetLength(a,4); writeln(Length(a),'|',a[0],a[1],'|',a[2],a[3]); end.
P
probe dyn-copy       <<'P'
var a,b: array of Integer; begin SetLength(a,3); a[0]:=1;a[1]:=2;a[2]:=3; b:=Copy(a,1,2); writeln(Length(b),'|',b[0],b[1]); end.
P
# ---- exceptions ----
probe exc-basic      <<'P'
uses sysutils;
begin try raise Exception.Create('boom'); except on E: Exception do writeln('caught:',E.Message); end; end.
P
probe exc-finally    <<'P'
uses sysutils;
begin try try writeln('t'); raise Exception.Create('x'); finally writeln('f'); end; except writeln('e'); end; end.
P
probe exc-divzero    <<'P'
uses sysutils; var a,b: Integer;
begin a:=1; b:=0; try writeln(a div b); except on E: Exception do writeln('div caught'); end; end.
P
probe exc-nested     <<'P'
uses sysutils;
begin try try raise Exception.Create('inner') except writeln('in'); raise; end except writeln('out'); end; end.
P

# ---- sysutils: numbers & dates ----
probe su-strtofloat  <<'P'
uses sysutils; begin writeln(StrToFloatDef('1.5',0):0:4,'|',StrToFloatDef('bad',9):0:4); end.
P
probe su-floattostr  <<'P'
uses sysutils; begin writeln(FloatToStr(1.5),'|',FloatToStr(0.1),'|',FloatToStr(100.0)); end.
P
probe su-encodedate  <<'P'
uses sysutils; var y,m,d: Word;
begin DecodeDate(EncodeDate(2026,8,4),y,m,d); writeln(y,'-',m,'-',d); end.
P
probe su-formatdt    <<'P'
uses sysutils; begin writeln(FormatDateTime('yyyy-mm-dd hh:nn:ss', EncodeDate(2026,8,4)+EncodeTime(13,5,9,0))); end.
P
probe su-comparestr  <<'P'
uses sysutils; begin writeln(CompareStr('a','b'),'|',CompareText('A','a'),'|',SameText('Ab','aB')); end.
P
# ---- sets & enums ----
probe set-ops        <<'P'
type TS = set of 1..8; var a,b: TS;
begin a:=[1,2,3]; b:=[3,4]; writeln(3 in (a*b),'|',4 in (a+b),'|',3 in (a-b)); end.
P
probe set-empty      <<'P'
type TS = set of 1..8; var a: TS; begin a:=[]; writeln(1 in a,'|',a=[]); end.
P
probe enum-ord       <<'P'
type TE=(eA,eB,eC); var e: TE; begin e:=eB; writeln(Ord(e),'|',Ord(High(TE)),'|',Ord(Low(TE))); end.
P
# ---- records & pointers ----
probe rec-nested     <<'P'
type TI=record x,y: Integer; end; TO_=record a: TI; n: Integer; end;
var o,p: TO_; begin o.a.x:=1; o.a.y:=2; o.n:=3; p:=o; p.a.x:=9; writeln(o.a.x,p.a.x,o.n); end.
P
probe rec-array      <<'P'
type TR=record v: Integer; end; var a: array[0..2] of TR; i: Integer;
begin for i:=0 to 2 do a[i].v:=i*10; writeln(a[0].v,'|',a[1].v,'|',a[2].v); end.
P
probe ptr-deref      <<'P'
var i: Integer; p: ^Integer; begin i:=5; p:=@i; p^:=7; writeln(i,'|',p^); end.
P
# ---- classes ----
probe cls-basic      <<'P'
type TC=class public v: Integer; constructor Create(a: Integer); function Twice: Integer; end;
constructor TC.Create(a: Integer); begin v:=a; end;
function TC.Twice: Integer; begin Twice:=v*2; end;
var c: TC; begin c:=TC.Create(21); writeln(c.v,'|',c.Twice); c.Free; end.
P
probe cls-virtual    <<'P'
type TB=class public function Name: string; virtual; end;
     TD=class(TB) public function Name: string; override; end;
function TB.Name: string; begin Name:='base'; end;
function TD.Name: string; begin Name:='derived'; end;
var b: TB; begin b:=TD.Create; writeln(b.Name); b.Free; end.
P
probe cls-inherited  <<'P'
type TB=class public function N: string; virtual; end;
     TD=class(TB) public function N: string; override; end;
function TB.N: string; begin N:='B'; end;
function TD.N: string; begin N:='D+'+inherited N; end;
var b: TB; begin b:=TD.Create; writeln(b.N); b.Free; end.
P
probe cls-is-as      <<'P'
type TB=class end; TD=class(TB) end;
var b: TB; begin b:=TD.Create; writeln(b is TD,'|',b is TB,'|',(b as TD)<>nil); b.Free; end.
P
# ---- TStringList ----
probe sl-addcount    <<'P'
uses classes; var l: TStringList;
begin l:=TStringList.Create; l.Add('a'); l.Add('b'); writeln(l.Count,'|',l[0],l[1]); l.Free; end.
P
probe sl-indexof     <<'P'
uses classes; var l: TStringList;
begin l:=TStringList.Create; l.Add('x'); l.Add('y'); writeln(l.IndexOf('y'),'|',l.IndexOf('z')); l.Free; end.
P
probe sl-text        <<'P'
uses classes; var l: TStringList;
begin l:=TStringList.Create; l.Add('p'); l.Add('q'); write(l.Text); l.Free; end.
P
probe sl-delete-clear <<'P'
uses classes; var l: TStringList;
begin l:=TStringList.Create; l.Add('a'); l.Add('b'); l.Add('c'); l.Delete(1);
writeln(l.Count,'|',l[0],l[1]); l.Clear; writeln(l.Count); l.Free; end.
P

# ---- sysutils: paths ----
probe su-extractname <<'P'
uses sysutils; begin writeln(ExtractFileName('/a/b/c.txt'),'|',ExtractFileName('c.txt'),'|',ExtractFileName('/a/')); end.
P
probe su-extractpath <<'P'
uses sysutils; begin writeln('[',ExtractFilePath('/a/b/c.txt'),']|[',ExtractFilePath('c.txt'),']'); end.
P
probe su-extractext  <<'P'
uses sysutils; begin writeln('[',ExtractFileExt('/a/b.c.txt'),']|[',ExtractFileExt('noext'),']|[',ExtractFileExt('.hidden'),']'); end.
P
probe su-changeext   <<'P'
uses sysutils; begin writeln(ChangeFileExt('a.txt','.bak'),'|',ChangeFileExt('noext','.x')); end.
P
# ---- numeric edges ----
probe int64-bounds   <<'P'
begin writeln(High(Int64),'|',Low(Int64)); end.
P
probe int-bounds     <<'P'
begin writeln(High(Integer),'|',Low(Integer),'|',High(Word),'|',High(Byte)); end.
P
probe abs-neg        <<'P'
var i: Integer; begin i:=-5; writeln(Abs(i),'|',Abs(-2.5):0:2); end.
P
probe sqr            <<'P'
begin writeln(Sqr(7),'|',Sqr(2.5):0:4); end.
P
# filed: compat-pascal-sqrt-requires-uses-math (Sqrt needs `uses math` here)
probe sqrt-no-uses   known <<'P'
begin writeln(Sqrt(16.0):0:4); end.
P
probe frac-int       <<'P'
begin writeln(Frac(2.75):0:4,'|',Int(2.75):0:4,'|',Int(-2.75):0:4); end.
P
probe round-banker   <<'P'
begin writeln(Round(0.5),'|',Round(1.5),'|',Round(2.5),'|',Round(-0.5),'|',Round(-1.5)); end.
P
probe trunc-neg      <<'P'
begin writeln(Trunc(-2.7),'|',Trunc(2.7),'|',Round(-2.7),'|',Round(2.7)); end.
P
probe str-proc       <<'P'
var s: string; begin Str(42, s); writeln('[',s,']'); Str(3.5:0:2, s); writeln('[',s,']'); end.
P
probe val-proc       <<'P'
var i, code: Integer; begin Val('123', i, code); writeln(i,'|',code); Val('12x', i, code); writeln(code); end.
P
probe odd-succ-pred  <<'P'
begin writeln(Odd(3),'|',Succ(5),'|',Pred(5),'|',Succ('a')); end.
P
# ---- TStringList: order & duplicates ----
probe sl-sorted      <<'P'
uses classes; var l: TStringList;
begin l:=TStringList.Create; l.Add('c'); l.Add('a'); l.Add('b'); l.Sort;
writeln(l[0],l[1],l[2]); l.Free; end.
P
probe sl-insert      <<'P'
uses classes; var l: TStringList;
begin l:=TStringList.Create; l.Add('a'); l.Add('c'); l.Insert(1,'b');
writeln(l.Count,'|',l[0],l[1],l[2]); l.Free; end.
P
# filed: feature-b-tstrings-commatext
probe sl-commatext   known <<'P'
uses classes; var l: TStringList;
begin l:=TStringList.Create; l.Add('a'); l.Add('b'); writeln(l.CommaText); l.Free; end.
P
probe sl-assign      <<'P'
uses classes; var a,b: TStringList;
begin a:=TStringList.Create; b:=TStringList.Create; a.Add('x'); a.Add('y');
b.Assign(a); a.Clear; writeln(b.Count,'|',b[0],b[1]); a.Free; b.Free; end.
P

# ---- string <-> number round trips ----
probe su-inttostr64  <<'P'
uses sysutils; begin writeln(IntToStr(High(Int64)),'|',IntToStr(Low(Int64))); end.
P
probe su-strtoint64  <<'P'
uses sysutils; begin writeln(StrToInt64('9223372036854775807'),'|',StrToInt64('-9223372036854775808')); end.
P
probe su-strtoint-ws <<'P'
uses sysutils; begin writeln(StrToIntDef(' 42',0),'|',StrToIntDef('42 ',0),'|',StrToIntDef('+42',0)); end.
P
probe su-strtoint-hex <<'P'
uses sysutils; begin writeln(StrToIntDef('$FF',0),'|',StrToIntDef('0x10',0)); end.
P
probe su-trystrtoint <<'P'
uses sysutils; var v: Integer;
begin writeln(TryStrToInt('7',v),'|',v,'|',TryStrToInt('no',v)); end.
P
# ---- case & comparison with non-letters ----
probe su-case-digits <<'P'
uses sysutils; begin writeln(UpperCase('a1[]~'),'|',LowerCase('A1[]~')); end.
P
probe su-comparetext-ord <<'P'
uses sysutils; begin writeln(CompareText('a','B')<0,'|',CompareStr('a','B')<0); end.
P
# ---- Copy / Delete / Insert edges ----
probe copy-zero      <<'P'
begin writeln('[',Copy('abcdef',3,0),']|[',Copy('abcdef',0,2),']|[',Copy('abcdef',7,2),']'); end.
P
probe copy-negative  <<'P'
begin writeln('[',Copy('abcdef',3,-1),']|[',Copy('abcdef',-2,3),']'); end.
P
probe delete-oob     <<'P'
var s: string; begin s:='abc'; Delete(s,5,2); writeln('[',s,']'); Delete(s,2,99); writeln('[',s,']'); end.
P
probe insert-oob     <<'P'
var s: string; begin s:='abc'; Insert('X',s,99); writeln('[',s,']'); s:='abc'; Insert('Y',s,0); writeln('[',s,']'); end.
P
probe concat-empty   <<'P'
begin writeln('[', Concat('a','','b'), ']|[', ''+'', ']'); end.
P
# ---- string comparison ordering ----
# filed URGENT: bug-p-string-char-relational-compares-lengths. A one-character
# literal is a Char, so '' < 'a' and 'ab' < 'b' are string-vs-Char comparisons,
# and those compare LENGTHS instead of content.
probe str-order      known <<'P'
begin writeln('A'<'a','|','Z'<'a','|',''<'a','|','ab'<'b'); end.
P
probe char-vs-str    <<'P'
var c: Char; s: string; begin c:='a'; s:='a'; writeln(s=c,'|',c<'b'); end.
P
# All four ORDERING operators in both operand orders, over pairs where content
# order and length order disagree. The case above only covered `=` and
# Char<Char, both of which were always right, which is how
# bug-p-string-char-relational-compares-lengths hid: the mixed pair fell through
# to an integer compare of the string HANDLE against the char ordinal.
probe char-vs-str-order <<'P'
var c: Char; s: string;
procedure P(b: Boolean); begin if b then write('T') else write('F'); end;
begin
  s:='a';  c:='z'; P(s<c);P(s>c);P(s<=c);P(s>=c);P(c<s);P(c>s);P(c<=s);P(c>=s);
  s:='ab'; c:='b'; P(s<c);P(s>c);P(s<=c);P(s>=c);P(c<s);P(c>s);
  s:='';   c:='z'; P(s<c);P(s>c);
  s:='z';  c:='z'; P(s<c);P(s<=c);P(s>=c);P(s>c);
  s:='zzz';c:='b'; P(s<c);P(s>c);
  s:='ab';         P(s<'b'); P(s>='b');
  writeln;
end.
P
# ---- for-loop and control flow edges ----
probe for-downto-zero <<'P'
var i, n: Integer; begin n:=0; for i:=3 downto 1 do n:=n*10+i; writeln(n); end.
P
# NOTE: does not read `i` after the loop. The value of a for-loop variable
# after the loop is UNDEFINED in Pascal, so a probe that printed it would be
# comparing two implementations' liberties, not finding a bug -- and it did
# report a divergence (fpc=0 pxx=5) that is nobody's defect.
probe for-empty      <<'P'
var i, n: Integer; begin n:=0; for i:=5 to 1 do n:=n+1; writeln(n); end.
P
probe case-else      <<'P'
var i, n: Integer; begin n:=0; for i:=1 to 4 do case i of 1,2: n:=n+1; 3: n:=n+10; else n:=n+100; end; writeln(n); end.
P
probe case-range     <<'P'
var i: Integer; begin i:=5; case i of 1..3: writeln('lo'); 4..6: writeln('mid'); else writeln('hi'); end; end.
P
probe while-break-cont <<'P'
var i, n: Integer;
begin i:=0; n:=0; while i<10 do begin i:=i+1; if i=3 then Continue; if i=6 then Break; n:=n+i; end; writeln(n,'|',i); end.
P
probe shortcircuit   <<'P'
var calls: Integer;
function F: Boolean; begin calls:=calls+1; F:=True; end;
begin calls:=0; if False and F then ; writeln(calls); if True or F then ; writeln(calls); end.
P

# ---- text file I/O ----
probe file-write-read <<'P'
var f: Text; s: string;
begin
  Assign(f,'/tmp/fdp_io.txt'); Rewrite(f); writeln(f,'line1'); writeln(f,'line2'); Close(f);
  Assign(f,'/tmp/fdp_io.txt'); Reset(f);
  while not Eof(f) do begin readln(f,s); writeln('[',s,']'); end;
  Close(f);
end.
P
# filed: bug-p-writeln-text-rejects-char (writeln(f,'a') -- 'a' is a Char)
probe file-append    known <<'P'
var f: Text; s: string;
begin
  Assign(f,'/tmp/fdp_ap.txt'); Rewrite(f); writeln(f,'a'); Close(f);
  Assign(f,'/tmp/fdp_ap.txt'); Append(f); writeln(f,'b'); Close(f);
  Assign(f,'/tmp/fdp_ap.txt'); Reset(f);
  while not Eof(f) do begin readln(f,s); write(s); end;
  Close(f); writeln;
end.
P
# filed: feature-b-rtl-missing-fpc-surface-2026-08 (Eoln)
probe file-eoln      known <<'P'
var f: Text; c: Char; n: Integer;
begin
  Assign(f,'/tmp/fdp_el.txt'); Rewrite(f); writeln(f,'ab'); Close(f);
  Assign(f,'/tmp/fdp_el.txt'); Reset(f); n:=0;
  while not Eoln(f) do begin read(f,c); n:=n+1; end;
  Close(f); writeln(n);
end.
P
probe file-missing   <<'P'
uses sysutils; var f: Text;
begin
  Assign(f,'/tmp/fdp_does_not_exist_zz');
  try Reset(f); writeln('opened'); Close(f); except writeln('raised'); end;
end.
P
# filed: bug-p-writeln-text-rejects-char
probe fileexists     known <<'P'
uses sysutils; var f: Text;
begin
  Assign(f,'/tmp/fdp_fe.txt'); Rewrite(f); writeln(f,'x'); Close(f);
  writeln(FileExists('/tmp/fdp_fe.txt'),'|',FileExists('/tmp/fdp_nope_zz'));
  DeleteFile('/tmp/fdp_fe.txt');
  writeln(FileExists('/tmp/fdp_fe.txt'));
end.
P
# ---- streams ----
probe stream-mem     <<'P'
uses classes; var m: TMemoryStream; b: array[0..3] of Byte; n: Integer;
begin
  m:=TMemoryStream.Create;
  b[0]:=1;b[1]:=2;b[2]:=3;b[3]:=4;
  m.Write(b,4); writeln(m.Size,'|',m.Position);
  m.Position:=0; b[0]:=0;b[1]:=0;
  n:=m.Read(b,2); writeln(n,'|',b[0],b[1],'|',m.Position);
  m.Free;
end.
P
# filed: feature-b-rtl-missing-fpc-surface-2026-08 (TSeekOrigin)
probe stream-seek    known <<'P'
uses classes; var m: TMemoryStream; b: array[0..7] of Byte; i: Integer;
begin
  m:=TMemoryStream.Create;
  for i:=0 to 7 do b[i]:=i;
  m.Write(b,8);
  writeln(m.Seek(2,soFromBeginning),'|',m.Seek(0,soFromEnd),'|',m.Size);
  m.Free;
end.
P
probe stream-strings <<'P'
uses classes; var m: TMemoryStream; l: TStringList;
begin
  l:=TStringList.Create; l.Add('one'); l.Add('two');
  m:=TMemoryStream.Create; l.SaveToStream(m);
  writeln(m.Size);
  m.Position:=0; l.Clear; l.LoadFromStream(m);
  writeln(l.Count,'|',l[0],'/',l[1]);
  l.Free; m.Free;
end.
P
# ---- TList ----
probe tlist-basic    <<'P'
uses classes; var l: TList; a, b: Integer;
begin
  a:=1; b:=2; l:=TList.Create;
  l.Add(@a); l.Add(@b);
  writeln(l.Count,'|',PInteger(l[0])^,PInteger(l[1])^,'|',l.IndexOf(@b));
  l.Delete(0); writeln(l.Count,'|',PInteger(l[0])^);
  l.Free;
end.
P
# ---- sorting a TStringList with duplicates ----
# TIE ORDER AMONG CASE-EQUAL STRINGS IS UNSPECIFIED — do not compare it.
# Measured on FPC: ('a','A') sorts to "a A" and ('A','a') to "A a" (stable), but
# ('b','a','b','A') gives "A a b b" — its quicksort is stable for a short run and
# not for a longer one. This case used to compare that exact order and PASSED
# only because pxx's Sort was case-SENSITIVE, which put 'A' before 'a' for an
# unrelated reason; fixing Sort to be case-insensitive like FPC's exposed it.
# Kept as a marker, with sl-sort-dups-stable-pairs below covering what IS
# specified: the multiset and the case-insensitive ordering.
probe sl-sort-dups known <<'P'
uses classes; var l: TStringList; i: Integer;
begin
  l:=TStringList.Create;
  l.Add('b'); l.Add('a'); l.Add('b'); l.Add('A');
  l.Sort;
  for i:=0 to l.Count-1 do write(l[i],' ');
  writeln('|',l.Count);
  l.Free;
end.
P
probe sl-sort-dups-defined <<'P'
uses classes, sysutils; var l: TStringList; i: Integer; ok: Boolean;
begin
  l:=TStringList.Create;
  l.Add('b'); l.Add('a'); l.Add('b'); l.Add('A');
  l.Sort;
  { what IS specified: the count, and a non-decreasing case-insensitive order }
  ok := True;
  for i:=1 to l.Count-1 do
    if CompareText(l[i-1], l[i]) > 0 then ok := False;
  writeln(l.Count, '|', ok, '|', LowerCase(l[0]), LowerCase(l[1]), LowerCase(l[2]), LowerCase(l[3]));
  l.Free;
end.
P
probe sl-sort-casesensitive <<'P'
uses classes; var l: TStringList;
begin
  l:=TStringList.Create;
  l.CaseSensitive := True;
  l.Add('b'); l.Add('a'); l.Add('B'); l.Add('A');
  l.Sort;
  { unambiguous: no two entries compare equal, so tie order cannot matter }
  writeln(l[0], l[1], l[2], l[3]);
  l.Free;
end.
P
# filed: feature-b-rtl-missing-fpc-surface-2026-08 (TStringList.Sorted)
probe sl-sorted-prop known <<'P'
uses classes; var l: TStringList; i: Integer;
begin
  l:=TStringList.Create; l.Sorted:=True;
  l.Add('c'); l.Add('a'); l.Add('b');
  for i:=0 to l.Count-1 do write(l[i]);
  writeln;
  l.Free;
end.
P
# ---- date/time round trips ----
probe dt-roundtrip   <<'P'
uses sysutils; var d: TDateTime; y,mo,dd: Word; h,mi,se,ms: Word;
begin
  d := EncodeDate(2026,2,28) + EncodeTime(23,59,58,0);
  DecodeDate(d,y,mo,dd); DecodeTime(d,h,mi,se,ms);
  writeln(y,'-',mo,'-',dd,' ',h,':',mi,':',se);
end.
P
probe dt-leapyear    <<'P'
uses sysutils; var y,mo,d: Word;
begin
  DecodeDate(EncodeDate(2024,2,29),y,mo,d); writeln(y,'-',mo,'-',d);
  writeln(IsLeapYear(2024),'|',IsLeapYear(2023),'|',IsLeapYear(2000),'|',IsLeapYear(1900));
end.
P
probe dt-dayofweek   <<'P'
uses sysutils; begin writeln(DayOfWeek(EncodeDate(2026,8,4))); end.
P
# filed: feature-b-rtl-missing-fpc-surface-2026-08 (IncMonth)
probe dt-incmonth    known <<'P'
uses sysutils; var y,mo,d: Word;
begin DecodeDate(IncMonth(EncodeDate(2026,1,31),1),y,mo,d); writeln(y,'-',mo,'-',d); end.
P

# ---- managed strings: copy semantics, aliasing, refcount-visible behaviour ----
probe str-cow        <<'P'
var a, b: string;
begin a := 'hello'; b := a; b[1] := 'J'; writeln(a,'|',b); end.
P
probe str-cow-setlen <<'P'
var a, b: string;
begin a := 'hello'; b := a; SetLength(b,3); writeln(a,'|',b,'|',Length(a)); end.
P
probe str-self-assign <<'P'
var a: string; begin a := 'abc'; a := a + a; writeln(a); a := Copy(a,2,3); writeln(a); end.
P
probe str-in-record  <<'P'
type TR = record s: string; n: Integer; end;
var x, y: TR;
begin x.s := 'one'; x.n := 1; y := x; y.s := 'two'; writeln(x.s,'|',y.s,'|',x.n); end.
P
# filed: URGENT bug-a-static-array-of-managed-whole-assign-loses-data
probe str-in-array   known <<'P'
var a, b: array[0..1] of string;
begin a[0] := 'p'; a[1] := 'q'; b := a; b[0] := 'z'; writeln(a[0],a[1],'|',b[0],b[1]); end.
P
probe str-dynarray-copy <<'P'
var a, b: array of string;
begin SetLength(a,2); a[0]:='p'; a[1]:='q'; b := Copy(a,0,2); b[0]:='z';
writeln(a[0],a[1],'|',b[0],b[1]); end.
P
# filed: decide-dynamic-array-value-vs-reference-semantics (Track U: value vs reference)
probe str-dynarray-ref known <<'P'
var a, b: array of string;
begin SetLength(a,2); a[0]:='p'; a[1]:='q'; b := a; b[0]:='z';
writeln(a[0],'|',b[0]); end.
P
# ---- parameter modes ----
probe param-var      <<'P'
procedure Bump(var x: Integer); begin x := x + 1; end;
var i: Integer; begin i := 1; Bump(i); writeln(i); end.
P
probe param-out      <<'P'
procedure Fill(out s: string); begin s := 'set'; end;
var t: string; begin t := 'before'; Fill(t); writeln(t); end.
P
probe param-const-str <<'P'
function F(const s: string): Integer; begin F := Length(s); end;
var a: string; begin a := 'abcd'; writeln(F(a),'|',F('xy'),'|',F('')); end.
P
probe param-value-str <<'P'
procedure P2(s: string); begin s := s + '!'; end;
var a: string; begin a := 'x'; P2(a); writeln(a); end.
P
probe param-openarray <<'P'
function Total(const a: array of Integer): Integer;
var i: Integer; begin Total := 0; for i := Low(a) to High(a) do Total := Total + a[i]; end;
var arr: array[0..2] of Integer;
begin arr[0]:=1; arr[1]:=2; arr[2]:=3; writeln(Total(arr),'|',Total([10,20])); end.
P
# filed: Low()/High() of an empty array constructor -- part of the same Track U call
probe param-openarray-empty known <<'P'
function Count(const a: array of Integer): Integer; begin Count := Length(a); end;
begin writeln(Count([]),'|',Low([1,2]),'|',High([1,2])); end.
P
# ---- records with managed fields returned from functions ----
probe rec-func-result <<'P'
type TR = record s: string; end;
function Make(const v: string): TR; begin Make.s := v; end;
var a, b: TR;
begin a := Make('one'); b := Make('two'); writeln(a.s,'|',b.s); end.
P
probe str-func-result-reuse <<'P'
function F(n: Integer): string; begin F := ''; while n > 0 do begin F := F + 'x'; n := n - 1; end; end;
var i: Integer; begin for i := 1 to 3 do write(F(i),' '); writeln; end.
P
# ---- string building in a loop (the leak/corruption shape) ----
probe str-concat-loop2 <<'P'
var s: string; i: Integer;
begin s := ''; for i := 1 to 50 do s := s + Chr(Ord('a') + (i mod 26)); writeln(Length(s),'|',s[1],s[50]); end.
P
probe str-nested-call <<'P'
function Wrap(const s: string): string; begin Wrap := '[' + s + ']'; end;
begin writeln(Wrap(Wrap(Wrap('x')))); end.
P

# filed URGENT: bug-a-virtual-method-int64-in-and-out-32bit. Correct on x86-64,
# so this case cannot catch it -- the probe only ever runs native. Kept as the
# reduced repro, next to the cases that led to it.
probe virtual-int64  <<'P'
type TB = class public function V(const x: Int64): Int64; virtual; end;
function TB.V(const x: Int64): Int64; begin V := x + 1; end;
var b: TB; begin b := TB.Create; writeln(b.V(5)); end.
P

# ---- sysutils string helpers not yet covered ----
probe su-quotedstr   <<'P'
uses sysutils; begin writeln(QuotedStr('ab'),'|',QuotedStr(''),'|',QuotedStr('a''b')); end.
P
probe su-stringofchar <<'P'
uses sysutils; begin writeln('[',StringOfChar('x',3),']|[',StringOfChar('x',0),']|[',StringOfChar('x',-1),']'); end.
P
probe su-lastdelim   <<'P'
uses sysutils; begin writeln(LastDelimiter('/','/a/b/c'),'|',LastDelimiter('/','abc'),'|',LastDelimiter('ab','xaybz')); end.
P
probe su-adjustlinebreaks <<'P'
uses sysutils; begin writeln(Length(AdjustLineBreaks('a'#10'b'))); end.
P
probe su-comparemem  <<'P'
uses sysutils; var a,b: array[0..3] of Byte;
begin a[0]:=1;a[1]:=2;a[2]:=3;a[3]:=4; b:=a; writeln(CompareMem(@a[0],@b[0],4)); b[2]:=9; writeln(CompareMem(@a[0],@b[0],4)); end.
P
probe su-fillchar    <<'P'
var a: array[0..3] of Byte; begin FillChar(a, 4, 7); writeln(a[0],a[1],a[2],a[3]); FillChar(a, 0, 9); writeln(a[0]); end.
P
probe su-move        <<'P'
var a,b: array[0..3] of Byte; begin a[0]:=1;a[1]:=2;a[2]:=3;a[3]:=4; Move(a,b,4); writeln(b[0],b[1],b[2],b[3]); end.
P
probe su-move-overlap <<'P'
var a: array[0..5] of Byte; i: Integer;
begin for i:=0 to 5 do a[i]:=i; Move(a[0],a[2],4); for i:=0 to 5 do write(a[i]); writeln; end.
P
# ---- ordinal / type conversion edges ----
probe chr-ord-high   <<'P'
begin writeln(Ord(Chr(255)),'|',Ord(#0),'|',Ord(#255)); end.
P
probe byte-overflow  <<'P'
var b: Byte; begin b := 255; b := b + 1; writeln(b); b := 0; b := b - 1; writeln(b); end.
P
probe shortint-wrap  <<'P'
var s: ShortInt; begin s := 127; s := s + 1; writeln(s); end.
P
probe int-div-by-neg <<'P'
begin writeln(7 div (-2),'|',(-7) div (-2),'|',(-8) div 2); end.
P
probe shl-shr-neg bydesign \
  'shl/shr compute at NATIVE width and never truncate to the declared type (decided 2026-08-11). FPC narrows -8 shr 1 back to 32 bits and prints 2147483644; pxx keeps the 64-bit 9223372036854775804. Permanent -- do NOT "fix" it to match.' <<'P'
var i: Integer; begin i := -8; writeln(i shr 1,'|',i shl 1); end.
P
probe int64-shift    <<'P'
var i: Int64; begin i := 1; writeln(i shl 40,'|',(i shl 62) shr 60); end.
P
probe and-or-xor-not <<'P'
begin writeln(12 and 10,'|',12 or 10,'|',12 xor 10,'|',not 12); end.
P
probe boolean-ops    <<'P'
begin writeln(True and False,'|',True or False,'|',not True,'|',True xor True); end.
P

# ---- generics (objfpc: generic / specialize) ----
# Generic CLASSES and RECORDS match FPC exactly. Only the inline specialization
# of a generic ROUTINE diverges — pxx wants the declaration form
# `specialize Max<Integer> as MaxInt;` — filed as
# compat-pascal-inline-generic-specialization.
probe gen-func-int   known <<'P'
generic function MaxOf<T>(a, b: T): T;
begin if a < b then Result := b else Result := a; end;
begin
  writeln(specialize MaxOf<Integer>(3, 9), '|', specialize MaxOf<Integer>(9, 3));
end.
P
probe gen-func-string known <<'P'
generic function MaxOf<T>(a, b: T): T;
begin if a < b then Result := b else Result := a; end;
begin
  writeln(specialize MaxOf<string>('abc', 'abd'));
end.
P
probe gen-swap-var   known <<'P'
generic procedure Swp<T>(var a, b: T);
var tmp: T;
begin tmp := a; a := b; b := tmp; end;
var x, y: Integer; s1, s2: string;
begin
  x := 1; y := 2; specialize Swp<Integer>(x, y);
  s1 := 'p'; s2 := 'q'; specialize Swp<string>(s1, s2);
  writeln(x, '|', y, '|', s1, '|', s2);
end.
P
probe gen-class-box  <<'P'
type
  generic TBox<T> = class
    Value: T;
    procedure SetIt(v: T);
    function GetIt: T;
  end;
procedure TBox.SetIt(v: T); begin Value := v; end;
function TBox.GetIt: T; begin Result := Value; end;
type TIntBox = specialize TBox<Integer>;
var b: TIntBox;
begin
  b := TIntBox.Create; b.SetIt(41); writeln(b.GetIt + 1); b.Free;
end.
P
probe gen-class-string <<'P'
type
  generic TBox<T> = class
    Value: T;
    procedure SetIt(v: T);
    function GetIt: T;
  end;
procedure TBox.SetIt(v: T); begin Value := v; end;
function TBox.GetIt: T; begin Result := Value; end;
type TStrBox = specialize TBox<string>;
var b: TStrBox;
begin
  b := TStrBox.Create; b.SetIt('hello'); writeln(b.GetIt, '|', Length(b.GetIt)); b.Free;
end.
P
probe gen-two-specializations <<'P'
type
  generic TPair<T> = class
    A, B: T;
    function Sum: T;
  end;
function TPair.Sum: T; begin Result := A + B; end;
type TI = specialize TPair<Integer>; TS = specialize TPair<string>;
var i: TI; s: TS;
begin
  i := TI.Create; i.A := 2; i.B := 3;
  s := TS.Create; s.A := 'ab'; s.B := 'cd';
  writeln(i.Sum, '|', s.Sum);
  i.Free; s.Free;
end.
P
probe gen-record     <<'P'
type
  generic TCell<T> = record
    V: T;
  end;
type TIC = specialize TCell<Integer>;
var c, d: TIC;
begin
  c.V := 7; d := c; d.V := 9;
  writeln(c.V, '|', d.V);
end.
P

# ---- operator overloading ----
probe op-overload-add <<'P'
type TVec = record X, Y: Integer; end;
operator + (const a, b: TVec): TVec;
begin Result.X := a.X + b.X; Result.Y := a.Y + b.Y; end;
var p, q, r: TVec;
begin
  p.X := 1; p.Y := 2; q.X := 10; q.Y := 20;
  r := p + q;
  writeln(r.X, '|', r.Y);
end.
P
probe op-overload-mul-scalar <<'P'
type TVec = record X, Y: Integer; end;
operator * (const a: TVec; k: Integer): TVec;
begin Result.X := a.X * k; Result.Y := a.Y * k; end;
var p, r: TVec;
begin
  p.X := 3; p.Y := 4; r := p * 5;
  writeln(r.X, '|', r.Y);
end.
P
probe op-overload-equal <<'P'
type TVec = record X, Y: Integer; end;
operator = (const a, b: TVec): Boolean;
begin Result := (a.X = b.X) and (a.Y = b.Y); end;
var p, q: TVec;
begin
  p.X := 1; p.Y := 2; q.X := 1; q.Y := 2;
  writeln(p = q);
  q.Y := 3;
  writeln(p = q);
end.
P
probe op-overload-chain <<'P'
type TVec = record X, Y: Integer; end;
operator + (const a, b: TVec): TVec;
begin Result.X := a.X + b.X; Result.Y := a.Y + b.Y; end;
var p, q, r, t: TVec;
begin
  p.X := 1; p.Y := 1; q.X := 2; q.Y := 2; r.X := 4; r.Y := 4;
  t := p + q + r;
  writeln(t.X, '|', t.Y);
end.
P

# ---- interfaces ----
probe iface-basic <<'P'
uses sysutils;
type
  IGreet = interface
    ['{11111111-2222-3333-4444-555555555555}']
    function Hello: string;
  end;
  TG = class(TInterfacedObject, IGreet)
    function Hello: string;
  end;
function TG.Hello: string; begin Result := 'hi'; end;
var g: IGreet;
begin
  g := TG.Create;
  writeln(g.Hello);
end.
P
probe iface-two-impls <<'P'
uses sysutils;
type
  IShape = interface
    ['{21111111-2222-3333-4444-555555555555}']
    function Area: Integer;
  end;
  TSq = class(TInterfacedObject, IShape)
    S: Integer;
    function Area: Integer;
  end;
  TRe = class(TInterfacedObject, IShape)
    W, H: Integer;
    function Area: Integer;
  end;
function TSq.Area: Integer; begin Result := S * S; end;
function TRe.Area: Integer; begin Result := W * H; end;
var a, b: IShape; sq: TSq; re: TRe;
begin
  sq := TSq.Create; sq.S := 4; a := sq;
  re := TRe.Create; re.W := 2; re.H := 5; b := re;
  writeln(a.Area, '|', b.Area);
end.
P
probe iface-as-cast <<'P'
uses sysutils;
type
  IA = interface ['{31111111-2222-3333-4444-555555555555}'] function Who: string; end;
  IB = interface ['{41111111-2222-3333-4444-555555555555}'] function Num: Integer; end;
  TBoth = class(TInterfacedObject, IA, IB)
    function Who: string;
    function Num: Integer;
  end;
function TBoth.Who: string; begin Result := 'both'; end;
function TBoth.Num: Integer; begin Result := 5; end;
var a: IA; b: IB;
begin
  a := TBoth.Create;
  b := a as IB;
  writeln(a.Who, '|', b.Num);
end.
P
probe iface-supports known <<'P'
uses sysutils;
type
  IA = interface ['{51111111-2222-3333-4444-555555555555}'] function Who: string; end;
  IB = interface ['{61111111-2222-3333-4444-555555555555}'] function Num: Integer; end;
  TOnlyA = class(TInterfacedObject, IA)
    function Who: string;
  end;
function TOnlyA.Who: string; begin Result := 'a'; end;
var a: IA; b: IB;
begin
  a := TOnlyA.Create;
  writeln(Supports(a, IB, b), '|', Supports(a, IA));
end.
P
probe iface-param-and-result <<'P'
uses sysutils;
type
  IV = interface ['{71111111-2222-3333-4444-555555555555}'] function V: Integer; end;
  TV = class(TInterfacedObject, IV) N: Integer; function V: Integer; end;
function TV.V: Integer; begin Result := N; end;
function Make(n: Integer): IV;
var t: TV;
begin t := TV.Create; t.N := n; Result := t; end;
function Twice(const x: IV): Integer;
begin Result := x.V * 2; end;
begin
  writeln(Twice(Make(21)));
end.
P

# ---- TStringList: Sorted / Duplicates ----
probe sl-sorted-on <<'P'
uses classes; var l: TStringList;
begin
  l := TStringList.Create;
  l.Add('pear'); l.Add('apple'); l.Add('mango');
  l.Sorted := True;
  writeln(l.Count, '|', l[0], '|', l[1], '|', l[2]);
  l.Free;
end.
P
probe sl-sorted-insert-order <<'P'
uses classes; var l: TStringList;
begin
  l := TStringList.Create;
  l.Sorted := True;
  l.Add('c'); l.Add('a'); l.Add('b');
  writeln(l[0], l[1], l[2]);
  l.Free;
end.
P
probe sl-sorted-indexof <<'P'
uses classes; var l: TStringList;
begin
  l := TStringList.Create;
  l.Add('delta'); l.Add('alpha'); l.Add('charlie');
  l.Sorted := True;
  writeln(l.IndexOf('alpha'), '|', l.IndexOf('delta'), '|', l.IndexOf('zulu'));
  l.Free;
end.
P
probe sl-dup-ignore <<'P'
uses classes; var l: TStringList;
begin
  l := TStringList.Create;
  l.Sorted := True;
  l.Duplicates := dupIgnore;
  l.Add('a'); l.Add('b'); l.Add('a');
  writeln(l.Count, '|', l[0], l[1]);
  l.Free;
end.
P
probe sl-sorted-off-keeps-order <<'P'
uses classes; var l: TStringList;
begin
  l := TStringList.Create;
  l.Add('z'); l.Add('y');
  l.Sorted := True;
  l.Sorted := False;
  l.Add('x');
  writeln(l[0], l[1], l[2]);
  l.Free;
end.
P
probe sl-sort-method <<'P'
uses classes; var l: TStringList;
begin
  l := TStringList.Create;
  l.Add('Banana'); l.Add('apple'); l.Add('Cherry');
  l.Sort;
  writeln(l[0], '|', l[1], '|', l[2]);
  l.Free;
end.
P


# ---- classes: inheritance, virtual dispatch, properties ----
probe cls-virtual-override <<'P'
type
  TA = class
    function Name: string; virtual;
    function Describe: string;
  end;
  TB = class(TA)
    function Name: string; override;
  end;
function TA.Name: string; begin Result := 'A'; end;
function TA.Describe: string; begin Result := '<' + Name + '>'; end;
function TB.Name: string; begin Result := 'B'; end;
var a: TA; b: TB;
begin
  a := TA.Create; b := TB.Create;
  writeln(a.Describe, '|', b.Describe);
  a.Free; b.Free;
end.
P
probe cls-inherited-call <<'P'
type
  TA = class
    function Name: string; virtual;
  end;
  TB = class(TA)
    function Name: string; override;
  end;
function TA.Name: string; begin Result := 'A'; end;
function TB.Name: string; begin Result := 'B+' + inherited Name; end;
var b: TB;
begin
  b := TB.Create; writeln(b.Name); b.Free;
end.
P
probe cls-polymorphic-var <<'P'
type
  TA = class function V: Integer; virtual; end;
  TB = class(TA) function V: Integer; override; end;
function TA.V: Integer; begin Result := 1; end;
function TB.V: Integer; begin Result := 2; end;
var a: TA;
begin
  a := TA.Create; write(a.V); a.Free;
  a := TB.Create; write(a.V); a.Free;
  writeln;
end.
P
probe cls-is-as <<'P'
type
  TA = class end;
  TB = class(TA) end;
  TC = class(TA) end;
var a: TA; b: TB;
begin
  b := TB.Create;
  a := b;
  writeln(a is TB, '|', a is TC, '|', a is TA);
  writeln((a as TB) = b);
  a.Free;
end.
P
probe cls-classname <<'P'
type
  TA = class end;
  TB = class(TA) end;
var b: TB;
begin
  b := TB.Create;
  writeln(b.ClassName, '|', b.InheritsFrom(TA), '|', TB.ClassName);
  b.Free;
end.
P
probe cls-property-getter <<'P'
type
  TBox = class
  private
    FV: Integer;
    function GetV: Integer;
    procedure SetV(x: Integer);
  public
    property V: Integer read GetV write SetV;
  end;
function TBox.GetV: Integer; begin Result := FV * 10; end;
procedure TBox.SetV(x: Integer); begin FV := x + 1; end;
var b: TBox;
begin
  b := TBox.Create;
  b.V := 4;
  writeln(b.V);
  b.Free;
end.
P
probe cls-property-field <<'P'
type
  TBox = class
  private
    FV: Integer;
  public
    property V: Integer read FV write FV;
  end;
var b: TBox;
begin
  b := TBox.Create; b.V := 7; writeln(b.V); b.Free;
end.
P
probe cls-constructor-chain <<'P'
type
  TA = class
    N: Integer;
    constructor Create(x: Integer);
  end;
  TB = class(TA)
    M: Integer;
    constructor Create(x, y: Integer);
  end;
constructor TA.Create(x: Integer); begin N := x; end;
constructor TB.Create(x, y: Integer); begin inherited Create(x); M := y; end;
var b: TB;
begin
  b := TB.Create(3, 4); writeln(b.N, '|', b.M); b.Free;
end.
P
probe cls-destructor-order <<'P'
type
  TA = class
    destructor Destroy; override;
  end;
  TB = class(TA)
    destructor Destroy; override;
  end;
destructor TA.Destroy; begin write('A'); inherited Destroy; end;
destructor TB.Destroy; begin write('B'); inherited Destroy; end;
var b: TB;
begin
  b := TB.Create; b.Free; writeln;
end.
P

# ---- exceptions: custom classes, nesting, re-raise ----
probe exc-custom-class <<'P'
uses sysutils;
type EMine = class(Exception) end;
begin
  try
    raise EMine.Create('boom');
  except
    on e: EMine do writeln('mine:', e.Message);
  end;
end.
P
probe exc-hierarchy-match <<'P'
uses sysutils;
type EBase = class(Exception) end;
     EDeriv = class(EBase) end;
begin
  try
    raise EDeriv.Create('x');
  except
    on e: EBase do writeln('base-caught');
  end;
end.
P
probe exc-reraise <<'P'
uses sysutils;
begin
  try
    try
      raise Exception.Create('inner');
    except
      on e: Exception do begin write('first:', e.Message, '|'); raise; end;
    end;
  except
    on e: Exception do writeln('second:', e.Message);
  end;
end.
P
probe exc-finally-order <<'P'
uses sysutils;
begin
  try
    try
      raise Exception.Create('x');
    finally
      write('fin|');
    end;
  except
    on e: Exception do writeln('caught');
  end;
end.
P
probe exc-nested-finally <<'P'
uses sysutils;
procedure P1;
begin
  try
    try
      raise Exception.Create('e');
    finally
      write('inner|');
    end;
  finally
    write('outer|');
  end;
end;
begin
  try P1 except on e: Exception do writeln('caught'); end;
end.
P
probe exc-else-branch <<'P'
uses sysutils;
type EOther = class(Exception) end;
begin
  try
    raise EOther.Create('z');
  except
    on e: EConvertError do writeln('convert');
    else writeln('else-branch');
  end;
end.
P

# ---- procedure / method pointers, nested procedures ----
probe procvar-plain <<'P'
type TFn = function(a, b: Integer): Integer;
function Add(a, b: Integer): Integer; begin Result := a + b; end;
function Sub(a, b: Integer): Integer; begin Result := a - b; end;
var f: TFn;
begin
  f := @Add; write(f(7, 3), '|');
  f := @Sub; writeln(f(7, 3));
end.
P
probe procvar-array <<'P'
type TFn = function(a, b: Integer): Integer;
function Add(a, b: Integer): Integer; begin Result := a + b; end;
function Mul(a, b: Integer): Integer; begin Result := a * b; end;
var fs: array[0..1] of TFn; i: Integer;
begin
  fs[0] := @Add; fs[1] := @Mul;
  for i := 0 to 1 do write(fs[i](3, 4), ' ');
  writeln;
end.
P
probe method-pointer <<'P'
type
  TObj = class
    N: Integer;
    function Get: Integer;
  end;
  TMeth = function: Integer of object;
function TObj.Get: Integer; begin Result := N * 3; end;
var o: TObj; m: TMeth;
begin
  o := TObj.Create; o.N := 5;
  m := @o.Get;
  writeln(m());
  o.Free;
end.
P
probe nested-proc-locals <<'P'
function Outer(n: Integer): Integer;
var acc: Integer;
  procedure Bump(k: Integer);
  begin acc := acc + k; end;
var i: Integer;
begin
  acc := 0;
  for i := 1 to n do Bump(i);
  Result := acc;
end;
begin
  writeln(Outer(4), '|', Outer(0));
end.
P

# ---- variant records, sets of enums, open arrays ----
probe variant-record <<'P'
type
  TKind = (kInt, kStr);
  TVal = record
    case Kind: TKind of
      kInt: (I: Integer);
      kStr: (C: array[0..3] of Char);
  end;
var v: TVal;
begin
  v.Kind := kInt; v.I := 65;
  writeln(Ord(v.Kind), '|', v.I, '|', Ord(v.C[0]));
end.
P
probe set-of-enum-ops <<'P'
type TC = (cRed, cGreen, cBlue, cWhite);
     TCs = set of TC;
var a, b: TCs;
begin
  a := [cRed, cGreen];
  b := [cGreen, cBlue];
  writeln((cGreen in a), '|', (cBlue in a));
  writeln((a + b) = [cRed, cGreen, cBlue], '|', (a * b) = [cGreen], '|', (a - b) = [cRed]);
  writeln(a <= [cRed, cGreen, cBlue], '|', [cRed] <= a);
end.
P
probe openarray-sum <<'P'
function SumOf(const a: array of Integer): Integer;
var i: Integer;
begin
  Result := 0;
  for i := Low(a) to High(a) do Result := Result + a[i];
end;
var arr: array[0..3] of Integer;
begin
  arr[0]:=1; arr[1]:=2; arr[2]:=3; arr[3]:=4;
  writeln(SumOf(arr), '|', SumOf([10, 20, 30]), '|', Length(arr));
end.
P
probe class-var-and-method <<'P'
type
  TCounter = class
    class function Twice(n: Integer): Integer;
  end;
class function TCounter.Twice(n: Integer): Integer; begin Result := n * 2; end;
begin
  writeln(TCounter.Twice(21));
end.
P

# ---- array of const / TVarRec, and the Format() that rides on it ----
probe aoc-vtypes <<'P'
uses SysUtils;
procedure Show(const a: array of const);
var i: Integer;
begin
  for i := Low(a) to High(a) do
    write(a[i].VType, ' ');
  writeln('| n=', Length(a));
end;
begin
  Show([1, 'str', 'c', True, 2.5]);
  Show([]);
end.
P
probe aoc-values <<'P'
uses SysUtils;
procedure Show(const a: array of const);
var i: Integer;
begin
  for i := Low(a) to High(a) do
    case a[i].VType of
      vtInteger: write('i:', a[i].VInteger, ' ');
      vtBoolean: write('b:', a[i].VBoolean, ' ');
      vtChar:    write('c:', a[i].VChar, ' ');
      vtAnsiString: write('s:', AnsiString(a[i].VAnsiString), ' ');
      vtExtended: write('e:', a[i].VExtended^:0:2, ' ');
    else write('?', a[i].VType, ' ');
    end;
  writeln;
end;
begin
  Show([7, True, 'z', 'hello', 1.25]);
end.
P
probe aoc-int64-and-pointer <<'P'
uses SysUtils;
procedure Show(const a: array of const);
var i: Integer;
begin
  for i := Low(a) to High(a) do write(a[i].VType, ' ');
  writeln;
end;
var p: Pointer;
begin
  p := nil;
  Show([Int64(5), p, nil]);
end.
P
probe format-basic <<'P'
uses SysUtils;
begin
  writeln(Format('%d|%s|%x|%u', [42, 'ab', 255, 7]));
end.
P
# '%c' is a PXX EXTENSION, not a parity gap. It is not in the Delphi/FPC Format
# spec, and FPC's behaviour on it is unspecified garbage — it re-emits the
# PREVIOUS conversion, so '%x|%c' of [255,'q'] prints 'FF|FF' while a lone '%c'
# prints nothing at all. pxx prints the character, as C's printf does. Kept as a
# [known] case so the divergence stays visible and cannot be "fixed" by accident.
probe format-pct-c-extension known <<'P'
uses SysUtils;
begin
  writeln(Format('%x|%c', [255, 'q']));
end.
P
probe format-n-grouping <<'P'
uses SysUtils;
begin
  writeln(Format('%n|%.0n|%.4n|%12n', [1234567.5, 1234.5, 1234.5, 1234.5]));
  writeln(Format('%n|%n|%n|%n', [-1234.5, 1000000.0, 999.0, 0.0]));
end.
P
probe format-currency <<'P'
uses SysUtils;
begin
  writeln(Format('%m|%.0m|%m', [1234.5, 1234.5, -1234.5]));
end.
P
probe format-star-width <<'P'
uses SysUtils;
begin
  writeln(Format('%*d|%-*d|%.*d|%*s', [6, 42, 6, 42, 5, 42, 6, 'ab']));
  writeln(Format('[%*d][%.*f][%*.*f]', [-6, 42, 3, 3.14159, 9, 2, 3.14159]));
end.
P
probe format-settings-defaults <<'P'
uses SysUtils;
begin
  writeln(ThousandSeparator, '|', CurrencyString, '|', CurrencyFormat, '|',
          NegCurrFormat, '|', CurrencyDecimals);
end.
P
probe format-width-and-precision <<'P'
uses SysUtils;
begin
  writeln(Format('[%5d][%-5d][%05d]', [42, 42, 42]));
  writeln(Format('[%8.3f][%s][%10s][%-10s]', [3.14159, 'x', 'r', 'l']));
end.
P
probe format-arg-index <<'P'
uses SysUtils;
begin
  writeln(Format('%1:s-%0:s', ['a', 'b']));
  writeln(Format('%0:s%1:s', ['a', 'b']));
end.
P
probe format-percent-and-exp <<'P'
uses SysUtils;
begin
  writeln(Format('100%%|%e', [1.5]));
end.
P

# ---- class helpers ----
# All three [known]: pxx's parser rejects `class helper for` outright
# (compat-pascal-class-helpers). Kept so the day it parses, the SEMANTICS are
# already under test — a helper method shadows a virtual one non-virtually, and
# an unqualified call inside a helper binds to the extended type's members.
probe class-helper-method known <<'P'
type
  TBox = class
    Value: Integer;
  end;
  TBoxHelper = class helper for TBox
    function Doubled: Integer;
  end;
function TBoxHelper.Doubled: Integer; begin Result := Value * 2; end;
var b: TBox;
begin
  b := TBox.Create;
  b.Value := 21;
  writeln(b.Doubled);
  b.Free;
end.
P
probe class-helper-shadowing known <<'P'
type
  TBase = class
    function Name: string; virtual;
  end;
  TBaseHelper = class helper for TBase
    function Name: string;
  end;
function TBase.Name: string; begin Result := 'base'; end;
function TBaseHelper.Name: string; begin Result := 'helper'; end;
var o: TBase;
begin
  o := TBase.Create;
  writeln(o.Name);
  writeln(TBase(o).Name);
  o.Free;
end.
P
probe class-helper-inherited known <<'P'
type
  TThing = class
    function Tag: string;
  end;
  TThingHelper = class helper for TThing
    function Tag2: string;
  end;
function TThing.Tag: string; begin Result := 'T'; end;
function TThingHelper.Tag2: string; begin Result := Tag + '2'; end;
var t: TThing;
begin
  t := TThing.Create;
  writeln(t.Tag2);
  t.Free;
end.
P

# ---- Currency ----
probe currency-arith <<'P'
var a, b: Currency;
begin
  a := 10.05;
  b := 3;
  writeln(a + b:0:4);
  writeln(a * b:0:4);
  writeln(a / 4:0:4);
  writeln(a - 20:0:4);
end.
P
probe currency-tostr <<'P'
uses SysUtils;
var a: Currency;
begin
  a := 1234.5;
  writeln(CurrToStr(a));
  writeln(FloatToStr(a));
  writeln(StrToCurr('12.25'):0:4);
end.
P
probe currency-precision <<'P'
var a: Currency;
begin
  a := 0.0001;
  writeln(a:0:4);
  a := 922337203685477.5;
  writeln(a:0:1);
end.
P

# ---- WideString / UnicodeString ----
probe widestring-basic <<'P'
var w: WideString; s: string;
begin
  w := 'hello';
  writeln(Length(w));
  s := w;
  writeln(s, '|', Length(s));
  w := w + ' there';
  writeln(Length(w));
end.
P
probe unicodestring-basic <<'P'
var u: UnicodeString; s: string;
begin
  u := 'abc';
  writeln(Length(u), '|', u[1], u[3]);
  s := u;
  writeln(s);
  writeln(Copy(u, 2, 2));
end.
P
probe widechar-ord <<'P'
var c: WideChar;
begin
  c := 'A';
  writeln(Ord(c));
  c := WideChar(233);
  writeln(Ord(c));
end.
P

# ---- dynamic arrays: SetLength, Copy, Insert/Delete, aliasing ----
probe dynarray-setlength-grow <<'P'
var a: array of Integer; i: Integer;
begin
  SetLength(a, 3);
  for i := 0 to 2 do a[i] := i * i;
  SetLength(a, 5);
  writeln(Length(a), '|', a[0], a[1], a[2], '|', a[3], '|', a[4]);
  SetLength(a, 2);
  writeln(Length(a), '|', a[0], a[1], '|', High(a));
end.
P
# [known] for the LAST line only: `Copy(a, 1, 2)[0]` — indexing a call result —
# does not parse (compat-pascal-index-a-function-call-result). Everything above
# it (dynamic-array aliasing vs Copy, an over-long Copy count) matches FPC.
probe dynarray-copy-and-alias known <<'P'
var a, b, c: array of Integer;
begin
  SetLength(a, 3); a[0] := 1; a[1] := 2; a[2] := 3;
  b := a;            { alias: same buffer }
  c := Copy(a, 0, 3);
  b[0] := 99;
  writeln(a[0], '|', b[0], '|', c[0]);
  writeln(Length(Copy(a, 1, 10)), '|', Copy(a, 1, 2)[0]);
end.
P
probe dynarray-insert-delete <<'P'
var a: array of Integer; i: Integer;
begin
  SetLength(a, 3); a[0] := 1; a[1] := 2; a[2] := 3;
  Insert(9, a, 1);
  for i := 0 to High(a) do write(a[i], ' ');
  writeln('| len=', Length(a));
  Delete(a, 0, 2);
  for i := 0 to High(a) do write(a[i], ' ');
  writeln('| len=', Length(a));
end.
P
probe dynarray-of-string <<'P'
var a: array of string; i: Integer;
begin
  SetLength(a, 3);
  a[0] := 'x'; a[1] := 'yy';
  writeln('[', a[0], '][', a[1], '][', a[2], ']|', Length(a[2]));
  SetLength(a, 1);
  SetLength(a, 3);
  writeln('[', a[1], ']|', Length(a[1]));
  for i := 0 to High(a) do a[i] := a[i] + '!';
  writeln('[', a[0], '][', a[1], ']');
end.
P
probe dynarray-empty <<'P'
var a: array of Integer;
begin
  writeln(Length(a), '|', High(a), '|', Low(a));
  SetLength(a, 0);
  writeln(Length(a), '|', High(a));
end.
P
# bug-p-member-off-a-constructor-result-yields-garbage (FIXED): the selector
# chain after a constructor call was DROPPED, so an Integer variable received
# the instance pointer and the program printed garbage silently. The Make()
# half was correct throughout and stays in the same case — it is what said the
# "member off a call result" machinery works and only the constructor exit was
# missing it. Untagged: must stay green.
probe member-off-a-constructor-result <<'P'
type
  TThing = class
    n: Integer;
    constructor Create(k: Integer);
    function Val: Integer;
  end;
constructor TThing.Create(k: Integer); begin n := k; end;
function TThing.Val: Integer; begin Result := n; end;
function Make(k: Integer): TThing; begin Result := TThing.Create(k); end;
var a, b, c, d: Integer;
begin
  a := TThing.Create(2).n;
  b := TThing.Create(3).Val;
  c := Make(4).n;
  d := Make(5).Val;
  writeln(a, '|', b, '|', c, '|', d);
end.
P
probe dynarray-index-call-result known <<'P'
type TArr = array of Integer;
function Make: TArr;
begin SetLength(Result, 2); Result[0] := 7; Result[1] := 8; end;
var s: string;
begin
  s := 'hello';
  writeln(Copy(s, 2, 3)[1]);
  writeln(Make[1]);
end.
P
probe dynarray-index-method-result known <<'P'
type
  TArr = array of Integer;
  TBag = class
    function Arr: TArr;
    function ArrP(k: Integer): TArr;
  end;
function TBag.Arr: TArr; begin SetLength(Result, 2); Result[0] := 5; Result[1] := 6; end;
function TBag.ArrP(k: Integer): TArr; begin SetLength(Result, 2); Result[0] := k; Result[1] := k + 1; end;
var b: TBag;
begin
  b := TBag.Create;
  writeln(b.Arr[1]);       { this one works today }
  writeln(b.ArrP(3)[0]);   { IR_UNSUPPORTED (AN_CALL) }
end.
P
probe dynarray-2d <<'P'
var g: array of array of Integer; i, j: Integer;
begin
  SetLength(g, 2);
  for i := 0 to 1 do SetLength(g[i], 3);
  for i := 0 to 1 do for j := 0 to 2 do g[i][j] := i * 10 + j;
  writeln(Length(g), '|', Length(g[0]), '|', g[1][2], '|', g[0][1]);
end.
P

# ---- sets ----
probe set-of-char-ops <<'P'
var s, t, u: set of Char; c: Char;
begin
  s := ['a'..'e'];
  t := ['d'..'h'];
  u := s * t;
  for c := 'a' to 'j' do if c in u then write(c);
  writeln('|');
  u := s + t;
  for c := 'a' to 'j' do if c in u then write(c);
  writeln('|');
  u := s - t;
  for c := 'a' to 'j' do if c in u then write(c);
  writeln;
end.
P
probe set-relations <<'P'
var a, b: set of Byte;
begin
  a := [1, 2, 3];
  b := [1, 2, 3, 4];
  writeln(a <= b, '|', b >= a, '|', a = b, '|', a <> b, '|', (a = [3, 2, 1]));
end.
P
probe set-include-exclude <<'P'
type TE = (eA, eB, eC, eD);
var s: set of TE; e: TE;
begin
  s := [eA, eC];
  Include(s, eB);
  Exclude(s, eA);
  for e := eA to eD do if e in s then write(Ord(e), ' ');
  writeln('| empty=', s = []);
end.
P
probe set-of-byte-full-range <<'P'
var s: set of Byte; i, n: Integer;
begin
  s := [];
  for i := 0 to 255 do if i mod 7 = 0 then Include(s, i);
  n := 0;
  for i := 0 to 255 do if i in s then Inc(n);
  writeln(n, '|', 0 in s, '|', 254 in s, '|', 255 in s);
end.
P

# ---- signed vs unsigned-narrow comparison ----
# Passes natively and is kept here anyway: the SAME expression is FALSE on
# aarch64 in both frontends (bug-a-aarch64-signed-vs-unsigned-narrow-comparison-
# is-wrong). This probe has no cross mode, so without a Pascal case on record
# the Pascal half of that bug is only visible through the C probe.
probe signed-vs-unsigned-narrow <<'P'
var n: Integer; b: Byte; w: Word; sm: SmallInt;
begin
  n := -1; b := 1; w := 1; sm := -1;
  writeln(n < b, '|', n < w, '|', sm < b, '|', n < 1, '|', b > n);
end.
P

# ---- atomics ----
probe interlocked-family <<'P'
{$IFDEF PXX} uses palatomic; {$ENDIF}
var n, r: LongInt; q, s: Int64;
begin
  n := 10;
  r := InterLockedIncrement(n);   writeln(r, '|', n);
  r := InterLockedDecrement(n);   writeln(r, '|', n);
  r := InterLockedExchange(n, 99); writeln(r, '|', n);
  r := InterLockedExchangeAdd(n, 5); writeln(r, '|', n);
  r := InterLockedCompareExchange(n, 7, 104); writeln(r, '|', n);
  r := InterLockedCompareExchange(n, 1, 999); writeln(r, '|', n);
  q := 100;
  s := InterLockedIncrement64(q);  writeln(s, '|', q);
  s := InterLockedDecrement64(q);  writeln(s, '|', q);
  s := InterLockedExchange64(q, 5000000000); writeln(s, '|', q);
  s := InterLockedExchangeAdd64(q, -50); writeln(s, '|', q);
  s := InterLockedCompareExchange64(q, 3, 4999999950); writeln(s, '|', q);
end.
P

# ---- threads ----
# Every case here prints only AFTER a join, and prints a total rather than an
# interleaving, so the expected output is deterministic. A thread probe that
# printed from inside the threads would report scheduling as a divergence.
probe thread-tthread-waitfor <<'P'
{$threadsafe on}
uses {$IFDEF FPC} cthreads, Classes, {$ELSE} palthreadobj, {$ENDIF} SysUtils;
type
  TAdder = class(TThread)
  public
    Total: Integer;
    procedure Execute; override;
  end;
procedure TAdder.Execute;
var i: Integer;
begin
  Total := 0;
  for i := 1 to 1000 do Total := Total + i;
end;
var t: TAdder;
begin
  t := TAdder.Create(True);
  t.FreeOnTerminate := False;
  t.Start;
  t.WaitFor;
  writeln(t.Total, '|', t.Finished);
  t.Free;
end.
P
probe thread-interlocked-counter <<'P'
{$threadsafe on}
uses {$IFDEF FPC} cthreads, Classes, {$ELSE} palthreadobj, palatomic, {$ENDIF} SysUtils;
var Counter: Integer;
type
  TBumper = class(TThread)
  public
    procedure Execute; override;
  end;
procedure TBumper.Execute;
var i: Integer;
begin
  for i := 1 to 5000 do InterLockedIncrement(Counter);
end;
var t: array[0..3] of TBumper; k: Integer;
begin
  Counter := 0;
  for k := 0 to 3 do
  begin
    t[k] := TBumper.Create(True);
    t[k].FreeOnTerminate := False;
    t[k].Start;
  end;
  for k := 0 to 3 do t[k].WaitFor;
  writeln(Counter);
  for k := 0 to 3 do t[k].Free;
end.
P
# THIS CASE FOUND TWO BUGS, ONE BEHIND THE OTHER. It was [known] for the
# t[k].Free compile failure (bug-p-free-and-destroy-only-work-on-a-simple-
# variable); once that was fixed it ran, and reported 7403 where FPC says
# 8000 — syncobjs.TCriticalSection was a NO-OP STUB
# (bug-b-criticalsection-was-a-no-op-stub). A [known] tag can hide a second,
# worse bug behind the first. Untagged now: both must stay fixed.
probe thread-critical-section <<'P'
{$threadsafe on}
uses {$IFDEF FPC} cthreads, Classes, {$ELSE} palthreadobj, {$ENDIF} SysUtils, SyncObjs;
var Counter: Integer; Lock: TCriticalSection;
type
  TBumper = class(TThread)
  public
    procedure Execute; override;
  end;
procedure TBumper.Execute;
var i: Integer;
begin
  for i := 1 to 2000 do
  begin
    Lock.Acquire;
    try Counter := Counter + 1; finally Lock.Release; end;
  end;
end;
var t: array[0..3] of TBumper; k: Integer;
begin
  Lock := TCriticalSection.Create;
  Counter := 0;
  for k := 0 to 3 do
  begin
    t[k] := TBumper.Create(True);
    t[k].FreeOnTerminate := False;
    t[k].Start;
  end;
  for k := 0 to 3 do t[k].WaitFor;
  writeln(Counter);
  for k := 0 to 3 do t[k].Free;
  Lock.Free;
end.
P
# WAS [known] TWICE OVER and is now green: pxx's WaitFor was a procedure where
# FPC's returns LongWord, and reading a procedure's non-existent result silently
# yields garbage instead of erroring
# (bug-p-procedure-method-in-an-expression-yields-garbage), which is why this
# reported a VALUE divergence rather than a compile failure. WaitFor is now
# `function WaitFor: LongWord` returning ReturnValue
# (compat-pascal-thread-api-surface-differs-from-fpc), so the tag comes off —
# a stale `known` lets a fixed case regress without failing the run.
probe thread-returnvalue-and-terminate <<'P'
{$threadsafe on}
uses {$IFDEF FPC} cthreads, Classes, {$ELSE} palthreadobj, {$ENDIF} SysUtils;
type
  TWorker = class(TThread)
  public
    procedure Execute; override;
  end;
procedure TWorker.Execute;
var i: Integer;
begin
  i := 0;
  while not Terminated do
  begin
    Inc(i);
    if i >= 100 then Terminate;
  end;
  ReturnValue := i;
end;
var t: TWorker;
begin
  t := TWorker.Create(True);
  t.FreeOnTerminate := False;
  t.Start;
  writeln(t.WaitFor, '|', t.ReturnValue, '|', t.Terminated);
  t.Free;
end.
P
# [known] BeginThread / TThreadID do not exist in the RTL
# (compat-pascal-thread-api-surface-differs-from-fpc).
# [known], but the REASON changed 2026-08-09: BeginThread / EndThread /
# TThreadID / WaitForThreadTerminate / CloseThread now exist and match FPC
# (compat-pascal-thread-api-surface-differs-from-fpc, verified on x86-64, i386,
# arm32 and aarch64). What is left is the uses-clause wart — FPC has them in
# `system`, pxx needs an explicit `uses palthreadobj`, exactly like
# bug-a-interlocked-family-needs-a-uses-clause-unlike-fpc. Adding palthreadobj
# to the {$ELSE} arm below would make it pass and would hide that wart, so the
# probe deliberately keeps FPC's own uses line.
probe thread-beginthread known <<'P'
{$threadsafe on}
uses {$IFDEF FPC} cthreads, {$ENDIF} SysUtils;
var Done: Integer;
function Body(p: Pointer): PtrInt;
begin
  Done := PtrInt(p) * 3;
  Result := 0;
end;
var h: TThreadID;
begin
  Done := -1;
  h := BeginThread(@Body, Pointer(PtrInt(14)));
  WaitForThreadTerminate(h, 0);
  writeln(Done);
end.
P
probe thread-local-string-building <<'P'
{$threadsafe on}
uses {$IFDEF FPC} cthreads, Classes, {$ELSE} palthreadobj, {$ENDIF} SysUtils;
type
  TBuilder = class(TThread)
  public
    Res: string;
    Seed: Integer;
    procedure Execute; override;
  end;
procedure TBuilder.Execute;
var i: Integer;
begin
  Res := '';
  for i := 1 to 200 do Res := Res + IntToStr(Seed);
end;
var t: array[0..2] of TBuilder; k: Integer;
begin
  for k := 0 to 2 do
  begin
    t[k] := TBuilder.Create(True);
    t[k].FreeOnTerminate := False;
    t[k].Seed := k + 1;
    t[k].Start;
  end;
  for k := 0 to 2 do t[k].WaitFor;
  for k := 0 to 2 do write(Length(t[k].Res), ':', Copy(t[k].Res, 1, 3), ' ');
  writeln;
  for k := 0 to 2 do t[k].Free;
end.
P

echo "---"
echo "new divergences: $new   known/filed: $known   by design: $bydesign   no-oracle skips: $skipped"
# A skip is not a pass. It is a case that silently compared nothing, so it is
# worth the same attention as a divergence until it is either fixed or removed.
[ "$skipped" -gt 0 ] && echo "(a SKIP is not a pass -- fix the case or drop it)"
[ "$new" -eq 0 ] && exit 0 || exit 1
