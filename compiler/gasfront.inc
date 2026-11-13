{ SPDX-License-Identifier: MPL-2.0 }
{ ===== GNU as source (.S / .s) -> ELF64 relocatable object =================

  The frontend Gibux's boot.S and entry.S needed to build with pxx alone
  (feature-gas-frontend, item 5 of feature-gibux-kernel-builds-with-pxx).
  `.S` goes through pxx's C preprocessor first, with __ASSEMBLER__ defined;
  `.s` does not. The output is always an ET_REL object (--emit-obj implied):
  an assembler has nothing to link on its own.

  NOT A SECOND ASSEMBLER. Every ordinary instruction is handed to the AT&T
  reader of GNU inline asm (asmatt.inc: AttEncodeOne -> AsmDispatch), the one
  x86-64 encoder. This file adds what a source FILE has and a template does
  not: sections, symbols, data directives, macros, branches to symbols, and
  relocations. Its single trick is the PLACEHOLDER: an operand that names a
  symbol is rewritten to a unique 32-bit constant, encoded, and the constant's
  bytes are then found in the instruction -- that offset is where the
  relocation goes. A placeholder that cannot be found exactly once is an error,
  never a guess (an 8- or 16-bit symbolic operand, say).

  `.code32` reuses the 64-bit encoder too. For every instruction a REX-free
  64-bit encoding exists, the bytes ARE the 32-bit encoding, provided:
    - a 32-bit address register is encoded by its number with no 0x67 prefix
      (AttGasCode32 in asmatt.inc), so `(%edi)` comes out as 32-bit `(%edi)`;
    - an absolute address uses the SIB no-base form (mod=00 rm=100 SIB=25),
      which both modes decode the same; never mod=00 rm=101, which is
      RIP-relative in one and absolute in the other;
    - no REX prefix appears (it is inc/dec in 32-bit mode) -- refused here.
  ljmp/lcall (EA/9A ptr16:32) exist only in 32-bit mode and are encoded here.

  Branches (jmp/call/jcc/loop) are encoded here: rel32 always (no relaxation
  to rel8 -- correct, a few bytes bigger than gas), loop/jecxz rel8 and local
  only. A target in the same section is resolved here; anything else becomes
  R_X86_64_PLT32 (call, jmp, jcc) the way current binutils writes it.

  Expressions follow gas's precedence, which is NOT C's: `|` `&` `^` bind
  tighter than `+` `-`. A value is constant + symbol - symbol; a difference of
  two symbols in one section folds to a constant at the end. }

const
  GAS_PH0 = $3C5A7E1D;
  GAS_PH1 = $2B4D6F19;
  GAS_PHR = $1E3D5C7B;   { the rip operand's: encoded absolute, then rewritten }
  GFK_ABS    = 0;   { unsigned/any absolute: data, and .code32 operands }
  GFK_ABS32S = 1;   { a sign-extended imm32/disp32 in 64-bit code }
  GFK_PC     = 2;   { pc-relative disp32 (rip operands) }
  GFK_PLT    = 3;   { a branch's rel32 }
  GFK_PC8    = 4;   { loop/jecxz rel8: local only }
  GAS_SYM_HASH = 4096;

var
  GasSecName: array of AnsiString;
  GasSecData: array of AnsiString;
  GasSecSize: array of Int64;
  GasSecType: array of Integer;      { 1 PROGBITS, 8 NOBITS, 7 NOTE }
  GasSecFlags: array of Integer;     { SHF_WRITE 1, SHF_ALLOC 2, SHF_EXECINSTR 4 }
  GasSecAlign: array of Integer;
  GasSecCount, GasCur, GasPrev: Integer;
  GasCode32: Boolean;

  GasSymName: array of AnsiString;
  GasSymSec: array of Integer;       { -1 undefined, -2 an equate's constant }
  GasSymVal: array of Int64;
  GasSymGlobal, GasSymWeak, GasSymHidden, GasSymUsed: array of Boolean;
  GasSymType: array of Integer;      { 0 notype, 1 object, 2 func }
  GasSymNext: array of Integer;
  GasSymOut: array of Integer;
  GasSymCount: Integer;
  GasSymHead: array[0..GAS_SYM_HASH - 1] of Integer;

  GasNumN, GasNumLast, GasNumFwd: array of Integer;
  GasNumCount: Integer;
  GasTmpCount: Integer;

  GasFixSec, GasFixSize, GasFixKind, GasFixP, GasFixM, GasFixLine: array of Integer;
  GasFixPos, GasFixEnd, GasFixC: array of Int64;
  GasFixCount: Integer;

  GasMacName, GasMacParams, GasMacBody: array of AnsiString;
  GasMacCount: Integer;
  GasMacCounter: Integer;
  GasDepth: Integer;

  { block collection: .macro .. .endm and .rept .. .endr }
  GasCollect: Integer;             { 0 none, 1 macro, 2 rept }
  GasCollectNest: Integer;
  GasCollectBody: AnsiString;
  GasCollectIdx: Integer;          { the macro being defined }
  GasReptCount: Int64;

  GasLineNo: Integer;
  GasFile: AnsiString;

  { the expression cursor }
  GasEx: AnsiString;
  GasExPos: Integer;

  { per-instruction placeholders }
  GasPhC: array[0..1] of Int64;
  GasPhP, GasPhM: array[0..1] of Integer;
  GasPhCount: Integer;
  GasRipC: Int64;
  GasRipP, GasRipM: Integer;
  GasHaveRip: Boolean;

  GasOut: array of Byte;
  GasOutLen: Integer;

procedure GasError(const msg: AnsiString);
begin
  ErrorNoPos(GasFile + ':' + AIntToStr(GasLineNo) + ': ' + msg);
end;

{ ---- small text helpers ---- }

function GasIsIdStart(c: Char): Boolean;
begin
  Result := ((c >= 'a') and (c <= 'z')) or ((c >= 'A') and (c <= 'Z')) or
            (c = '_') or (c = '.') or (c = '$');
end;

function GasIsIdChar(c: Char): Boolean;
begin
  Result := GasIsIdStart(c) or ((c >= '0') and (c <= '9'));
end;

function GasLowerCh(c: Char): Char;
begin
  if (c >= 'A') and (c <= 'Z') then Result := Chr(Ord(c) + 32) else Result := c;
end;

function GasIsDigit(c: Char): Boolean;
begin
  Result := (c >= '0') and (c <= '9');
end;

function GasTrim(const s: AnsiString): AnsiString;
var a, b: Integer;
begin
  a := 1; b := Length(s);
  while (a <= b) and ((s[a] = ' ') or (s[a] = #9) or (s[a] = #13)) do Inc(a);
  while (b >= a) and ((s[b] = ' ') or (s[b] = #9) or (s[b] = #13)) do Dec(b);
  Result := Copy(s, a, b - a + 1);
end;

function GasLower(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString;
begin
  r := s;
  for i := 1 to Length(r) do
    if (r[i] >= 'A') and (r[i] <= 'Z') then r[i] := Chr(Ord(r[i]) + 32);
  Result := r;
end;

{ Split at top-level commas: not inside ( ) or a "string". }
function GasSplitCount(const s: AnsiString): Integer; forward;
function GasSplitItem(const s: AnsiString; k: Integer): AnsiString;
var i, depth, n, start: Integer; inStr: Boolean;
begin
  Result := '';
  depth := 0; n := 0; start := 1; inStr := False;
  i := 1;
  while i <= Length(s) do
  begin
    if inStr then
    begin
      if s[i] = '\' then Inc(i)
      else if s[i] = '"' then inStr := False;
    end
    else if s[i] = '"' then inStr := True
    else if s[i] = '(' then Inc(depth)
    else if s[i] = ')' then Dec(depth)
    else if (s[i] = ',') and (depth = 0) then
    begin
      if n = k then begin Result := GasTrim(Copy(s, start, i - start)); Exit; end;
      Inc(n);
      start := i + 1;
    end;
    Inc(i);
  end;
  if n = k then Result := GasTrim(Copy(s, start, Length(s) - start + 1));
end;

function GasSplitCount(const s: AnsiString): Integer;
var i, depth, n: Integer; inStr: Boolean;
begin
  if GasTrim(s) = '' then begin Result := 0; Exit; end;
  depth := 0; n := 1; inStr := False;
  i := 1;
  while i <= Length(s) do
  begin
    if inStr then
    begin
      if s[i] = '\' then Inc(i)
      else if s[i] = '"' then inStr := False;
    end
    else if s[i] = '"' then inStr := True
    else if s[i] = '(' then Inc(depth)
    else if s[i] = ')' then Dec(depth)
    else if (s[i] = ',') and (depth = 0) then Inc(n);
    Inc(i);
  end;
  Result := n;
end;

{ ---- sections ---- }

function GasFindSec(const nm: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to GasSecCount - 1 do
    if GasSecName[i] = nm then begin Result := i; Exit; end;
end;

function GasAddSec(const nm: AnsiString; typ, flags: Integer): Integer;
var k: Integer;
begin
  k := GasSecCount;
  Inc(GasSecCount);
  SetLength(GasSecName, GasSecCount);
  SetLength(GasSecData, GasSecCount);
  SetLength(GasSecSize, GasSecCount);
  SetLength(GasSecType, GasSecCount);
  SetLength(GasSecFlags, GasSecCount);
  SetLength(GasSecAlign, GasSecCount);
  GasSecName[k] := nm;
  GasSecData[k] := '';
  GasSecSize[k] := 0;
  GasSecType[k] := typ;
  GasSecFlags[k] := flags;
  GasSecAlign[k] := 1;
  Result := k;
end;

function GasStartsWith(const s, p: AnsiString): Boolean;
begin
  Result := (Length(s) >= Length(p)) and (Copy(s, 1, Length(p)) = p);
end;

{ The section a bare name means, gas's defaults by name. }
procedure GasSwitchTo(const nm: AnsiString; const flagStr, typStr: AnsiString; haveFlags: Boolean);
var k, typ, flags, i: Integer;
begin
  k := GasFindSec(nm);
  if k < 0 then
  begin
    typ := 1; flags := 2;
    if GasStartsWith(nm, '.text') then flags := 6
    else if GasStartsWith(nm, '.data') then flags := 3
    else if GasStartsWith(nm, '.bss') then begin flags := 3; typ := 8; end
    else if GasStartsWith(nm, '.rodata') then flags := 2
    else if GasStartsWith(nm, '.note') then begin flags := 0; if nm <> '.note.GNU-stack' then typ := 7; end
    else if GasStartsWith(nm, '.init_array') then begin flags := 3; typ := 14; end
    else if GasStartsWith(nm, '.fini_array') then begin flags := 3; typ := 15; end
    else if not haveFlags then flags := 0;
    if haveFlags then
    begin
      flags := 0;
      for i := 1 to Length(flagStr) do
        case flagStr[i] of
          'a': flags := flags or 2;
          'w': flags := flags or 1;
          'x': flags := flags or 4;
          'M', 'S', 'G', 'T', 'o', 'R', 'd', 'e': ;
        else
          GasError('section flag ''' + flagStr[i] + ''' is not supported');
        end;
    end;
    if typStr <> '' then
    begin
      if (typStr = 'progbits') then typ := 1
      else if typStr = 'nobits' then typ := 8
      else if typStr = 'note' then typ := 7
      else if typStr = 'init_array' then typ := 14
      else if typStr = 'fini_array' then typ := 15
      else GasError('section type @' + typStr + ' is not supported');
    end;
    k := GasAddSec(nm, typ, flags);
  end;
  if k <> GasCur then begin GasPrev := GasCur; GasCur := k; end;
end;

function GasSecIsExec(k: Integer): Boolean;
begin
  Result := (GasSecFlags[k] and 4) <> 0;
end;

function GasCurOff: Int64;
begin
  if GasSecType[GasCur] = 8 then Result := GasSecSize[GasCur]
  else Result := Length(GasSecData[GasCur]);
end;

procedure GasEmitByte(b: Integer);
begin
  if GasSecType[GasCur] = 8 then
  begin
    if (b and $FF) <> 0 then
      GasError('a nonzero byte in ' + GasSecName[GasCur] + ', which has no contents (@nobits)');
    GasSecSize[GasCur] := GasSecSize[GasCur] + 1;
    Exit;
  end;
  GasSecData[GasCur] := GasSecData[GasCur] + Chr(b and $FF);
end;

procedure GasEmitLE(v: Int64; n: Integer);
var i: Integer;
begin
  for i := 0 to n - 1 do
    GasEmitByte(Integer((v shr (8 * i)) and $FF));
end;

procedure GasEmitFill(count: Int64; fill: Integer);
var chunk: AnsiString; k: Integer;
begin
  if count <= 0 then Exit;
  if GasSecType[GasCur] = 8 then
  begin
    if fill <> 0 then GasError('a nonzero fill in a @nobits section');
    GasSecSize[GasCur] := GasSecSize[GasCur] + count;
    Exit;
  end;
  if count > 64 * 1024 * 1024 then GasError('a fill of ' + AIntToStr(count) + ' bytes');
  SetLength(chunk, Integer(count));
  for k := 1 to Integer(count) do chunk[k] := Chr(fill and $FF);
  GasSecData[GasCur] := GasSecData[GasCur] + chunk;
end;

procedure GasPatch(sec: Integer; pos, v: Int64; n: Integer);
var s: AnsiString; i: Integer;
begin
  s := GasSecData[sec];
  for i := 0 to n - 1 do
    s[Integer(pos) + 1 + i] := Chr(Integer((v shr (8 * i)) and $FF));
  GasSecData[sec] := s;
end;

procedure GasAlign(a: Int64; fill: Integer; useFill: Boolean);
var off, pad: Int64; f: Integer;
begin
  if a <= 1 then Exit;
  if (a and (a - 1)) <> 0 then GasError('alignment ' + AIntToStr(a) + ' is not a power of two');
  if a > GasSecAlign[GasCur] then GasSecAlign[GasCur] := Integer(a);
  off := GasCurOff;
  pad := (a - (off mod a)) mod a;
  f := fill;
  if (not useFill) and GasSecIsExec(GasCur) then f := $90;
  GasEmitFill(pad, f);
end;

{ ---- symbols ---- }

function GasHashName(const s: AnsiString): Integer;
var i: Integer; h: Int64;
begin
  h := 5381;
  for i := 1 to Length(s) do h := ((h * 33) xor Ord(s[i])) and $FFFFFF;
  Result := Integer(h and (GAS_SYM_HASH - 1));
end;

function GasNewSym(const nm: AnsiString; hidden: Boolean): Integer;
var k, h: Integer;
begin
  k := GasSymCount;
  Inc(GasSymCount);
  SetLength(GasSymName, GasSymCount);
  SetLength(GasSymSec, GasSymCount);
  SetLength(GasSymVal, GasSymCount);
  SetLength(GasSymGlobal, GasSymCount);
  SetLength(GasSymWeak, GasSymCount);
  SetLength(GasSymHidden, GasSymCount);
  SetLength(GasSymUsed, GasSymCount);
  SetLength(GasSymType, GasSymCount);
  SetLength(GasSymNext, GasSymCount);
  SetLength(GasSymOut, GasSymCount);
  GasSymName[k] := nm;
  GasSymSec[k] := -1;
  GasSymVal[k] := 0;
  GasSymGlobal[k] := False;
  GasSymWeak[k] := False;
  GasSymHidden[k] := hidden;
  GasSymUsed[k] := False;
  GasSymType[k] := 0;
  GasSymOut[k] := 0;
  GasSymNext[k] := -1;
  if not hidden then
  begin
    h := GasHashName(nm);
    GasSymNext[k] := GasSymHead[h];
    GasSymHead[h] := k;
  end;
  Result := k;
end;

function GasSym(const nm: AnsiString): Integer;
var k: Integer;
begin
  k := GasSymHead[GasHashName(nm)];
  while k >= 0 do
  begin
    if GasSymName[k] = nm then begin Result := k; Exit; end;
    k := GasSymNext[k];
  end;
  Result := GasNewSym(nm, False);
end;

procedure GasDefine(k: Integer);
begin
  if GasSymSec[k] <> -1 then
    GasError('symbol ''' + GasSymName[k] + ''' is already defined');
  GasSymSec[k] := GasCur;
  GasSymVal[k] := GasCurOff;
end;

{ A local label `N:`. `Nb` is the newest definition, `Nf` the next one: a
  forward reference makes the symbol the next definition will take. }
function GasNumSlot(n: Integer): Integer;
var i: Integer;
begin
  for i := 0 to GasNumCount - 1 do
    if GasNumN[i] = n then begin Result := i; Exit; end;
  i := GasNumCount;
  Inc(GasNumCount);
  SetLength(GasNumN, GasNumCount);
  SetLength(GasNumLast, GasNumCount);
  SetLength(GasNumFwd, GasNumCount);
  GasNumN[i] := n;
  GasNumLast[i] := -1;
  GasNumFwd[i] := -1;
  Result := i;
end;

procedure GasDefineNum(n: Integer);
var s, k: Integer;
begin
  s := GasNumSlot(n);
  k := GasNumFwd[s];
  if k < 0 then k := GasNewSym(AIntToStr(n) + ':', True);
  GasNumFwd[s] := -1;
  GasDefine(k);
  GasNumLast[s] := k;
end;

function GasNumRef(n: Integer; fwd: Boolean): Integer;
var s: Integer;
begin
  s := GasNumSlot(n);
  if fwd then
  begin
    if GasNumFwd[s] < 0 then GasNumFwd[s] := GasNewSym(AIntToStr(n) + 'f', True);
    Result := GasNumFwd[s];
  end
  else
  begin
    if GasNumLast[s] < 0 then GasError(AIntToStr(n) + 'b: no label ' + AIntToStr(n) + ': precedes it');
    Result := GasNumLast[s];
  end;
end;

{ ---- expressions: value = c + P - M ---- }

procedure GasExpr(var c: Int64; var p, m: Integer); forward;

procedure GasExSkip;
begin
  while (GasExPos <= Length(GasEx)) and ((GasEx[GasExPos] = ' ') or (GasEx[GasExPos] = #9)) do
    Inc(GasExPos);
end;

function GasExPeek: Char;
begin
  GasExSkip;
  if GasExPos > Length(GasEx) then Result := #0 else Result := GasEx[GasExPos];
end;

function GasExPeek2: Char;
begin
  if GasExPos + 1 > Length(GasEx) then Result := #0 else Result := GasEx[GasExPos + 1];
end;

procedure GasNeedConst(p, m: Integer; const op: AnsiString);
begin
  if (p >= 0) or (m >= 0) then
    GasError('operator ' + op + ' applied to a symbol''s address; only + and - may be');
end;

{ An equate (name = constant) reads as its constant. }
procedure GasFoldEquate(var c: Int64; var p: Integer);
begin
  if (p >= 0) and (GasSymSec[p] = -2) then
  begin
    c := c + GasSymVal[p];
    p := -1;
  end;
end;

procedure GasExPrimary(var c: Int64; var p, m: Integer);
var ch: Char; st, n: Integer; nm: AnsiString; v: Int64; d: Integer; t: Integer;
begin
  c := 0; p := -1; m := -1;
  ch := GasExPeek;
  if ch = '(' then
  begin
    Inc(GasExPos);
    GasExpr(c, p, m);
    if GasExPeek <> ')' then GasError('expected ) in expression: ' + GasEx);
    Inc(GasExPos);
    Exit;
  end;
  if ch = '''' then
  begin
    { 'c : a character constant (gas also accepts a closing quote) }
    Inc(GasExPos);
    if GasExPos > Length(GasEx) then GasError('character constant at end of line');
    if GasEx[GasExPos] = '\' then
    begin
      Inc(GasExPos);
      case GasEx[GasExPos] of
        'n': c := 10; 't': c := 9; 'r': c := 13; '0': c := 0;
      else c := Ord(GasEx[GasExPos]);
      end;
    end
    else c := Ord(GasEx[GasExPos]);
    Inc(GasExPos);
    if (GasExPos <= Length(GasEx)) and (GasEx[GasExPos] = '''') then Inc(GasExPos);
    Exit;
  end;
  if GasIsDigit(ch) then
  begin
    st := GasExPos;
    { a local label reference: digits then b/f, not followed by more of a word }
    n := GasExPos;
    while (n <= Length(GasEx)) and GasIsDigit(GasEx[n]) do Inc(n);
    if (n <= Length(GasEx)) and ((GasEx[n] = 'b') or (GasEx[n] = 'f')) and
       ((n + 1 > Length(GasEx)) or not GasIsIdChar(GasEx[n + 1])) and
       not ((GasEx[st] = '0') and (n = st + 1) and (GasEx[n] = 'b') and
            (n + 1 <= Length(GasEx)) and GasIsDigit(GasEx[n + 1])) then
    begin
      t := 0;
      while GasExPos < n do begin t := t * 10 + (Ord(GasEx[GasExPos]) - 48); Inc(GasExPos); end;
      p := GasNumRef(t, GasEx[n] = 'f');
      GasExPos := n + 1;
      Exit;
    end;
    v := 0;
    if (ch = '0') and ((GasExPeek2 = 'x') or (GasExPeek2 = 'X')) then
    begin
      GasExPos := GasExPos + 2;
      while GasExPos <= Length(GasEx) do
      begin
        ch := GasEx[GasExPos];
        if GasIsDigit(ch) then d := Ord(ch) - 48
        else if (ch >= 'a') and (ch <= 'f') then d := Ord(ch) - 87
        else if (ch >= 'A') and (ch <= 'F') then d := Ord(ch) - 55
        else Break;
        v := (v shl 4) or d;
        Inc(GasExPos);
      end;
    end
    else if (ch = '0') and ((GasExPeek2 = 'b') or (GasExPeek2 = 'B')) then
    begin
      GasExPos := GasExPos + 2;
      while (GasExPos <= Length(GasEx)) and ((GasEx[GasExPos] = '0') or (GasEx[GasExPos] = '1')) do
      begin
        v := (v shl 1) or (Ord(GasEx[GasExPos]) - 48);
        Inc(GasExPos);
      end;
    end
    else if (ch = '0') and GasIsDigit(GasExPeek2) then
    begin
      Inc(GasExPos);
      while (GasExPos <= Length(GasEx)) and (GasEx[GasExPos] >= '0') and (GasEx[GasExPos] <= '7') do
      begin
        v := (v shl 3) or (Ord(GasEx[GasExPos]) - 48);
        Inc(GasExPos);
      end;
    end
    else
      while (GasExPos <= Length(GasEx)) and GasIsDigit(GasEx[GasExPos]) do
      begin
        v := v * 10 + (Ord(GasEx[GasExPos]) - 48);
        Inc(GasExPos);
      end;
    if (GasExPos <= Length(GasEx)) and GasIsIdChar(GasEx[GasExPos]) then
      GasError('malformed number in expression: ' + GasEx);
    c := v;
    Exit;
  end;
  if GasIsIdStart(ch) then
  begin
    st := GasExPos;
    while (GasExPos <= Length(GasEx)) and GasIsIdChar(GasEx[GasExPos]) do Inc(GasExPos);
    nm := Copy(GasEx, st, GasExPos - st);
    if nm = '.' then
    begin
      { the current location }
      Inc(GasTmpCount);
      p := GasNewSym('.', True);
      GasSymSec[p] := GasCur;
      GasSymVal[p] := GasCurOff;
      Exit;
    end;
    p := GasSym(nm);
    GasFoldEquate(c, p);
    Exit;
  end;
  if ch = '%' then
    GasError('a register where an expression was expected: ' + GasEx);
  GasError('cannot read the expression: ' + GasEx);
end;

procedure GasExUnary(var c: Int64; var p, m: Integer);
var ch: Char; t: Integer;
begin
  ch := GasExPeek;
  if ch = '-' then
  begin
    Inc(GasExPos);
    GasExUnary(c, p, m);
    c := -c;
    t := p; p := m; m := t;
    Exit;
  end;
  if ch = '+' then begin Inc(GasExPos); GasExUnary(c, p, m); Exit; end;
  if ch = '~' then
  begin
    Inc(GasExPos); GasExUnary(c, p, m); GasNeedConst(p, m, '~'); c := not c; Exit;
  end;
  if ch = '!' then
  begin
    Inc(GasExPos); GasExUnary(c, p, m); GasNeedConst(p, m, '!');
    if c = 0 then c := 1 else c := 0;
    Exit;
  end;
  GasExPrimary(c, p, m);
end;

procedure GasExMul(var c: Int64; var p, m: Integer);
var c2: Int64; p2, m2: Integer; ch, ch2: Char;
begin
  GasExUnary(c, p, m);
  while True do
  begin
    ch := GasExPeek; ch2 := GasExPeek2;
    if (ch = '*') or (ch = '/') or (ch = '%') then
    begin
      Inc(GasExPos);
      GasExUnary(c2, p2, m2);
      GasNeedConst(p, m, ch); GasNeedConst(p2, m2, ch);
      if ch = '*' then c := c * c2
      else
      begin
        if c2 = 0 then GasError('division by zero in expression: ' + GasEx);
        if ch = '/' then c := c div c2 else c := c mod c2;
      end;
    end
    else if ((ch = '<') and (ch2 = '<')) or ((ch = '>') and (ch2 = '>')) then
    begin
      GasExPos := GasExPos + 2;
      GasExUnary(c2, p2, m2);
      GasNeedConst(p, m, ch + ch2); GasNeedConst(p2, m2, ch + ch2);
      if ch = '<' then c := c shl Integer(c2)
      else if c >= 0 then c := c shr Integer(c2)
      else c := not ((not c) shr Integer(c2));   { gas shifts right arithmetically }
    end
    else Break;
  end;
end;

procedure GasExBit(var c: Int64; var p, m: Integer);
var c2: Int64; p2, m2: Integer; ch: Char;
begin
  GasExMul(c, p, m);
  while True do
  begin
    ch := GasExPeek;
    if ((ch = '|') and (GasExPeek2 <> '|')) or ((ch = '&') and (GasExPeek2 <> '&')) or (ch = '^') or
       ((ch = '!') and (GasExPeek2 <> '=')) then
    begin
      Inc(GasExPos);
      GasExMul(c2, p2, m2);
      GasNeedConst(p, m, ch); GasNeedConst(p2, m2, ch);
      if ch = '|' then c := c or c2
      else if ch = '&' then c := c and c2
      else if ch = '^' then c := c xor c2
      else c := c or (not c2);
    end
    else Break;
  end;
end;

procedure GasExAdd(var c: Int64; var p, m: Integer);
var c2: Int64; p2, m2, t: Integer; ch: Char;
begin
  GasExBit(c, p, m);
  while True do
  begin
    ch := GasExPeek;
    if (ch = '+') or (ch = '-') then
    begin
      Inc(GasExPos);
      GasExBit(c2, p2, m2);
      if ch = '-' then
      begin
        c2 := -c2;
        t := p2; p2 := m2; m2 := t;
      end;
      c := c + c2;
      { combine: at most one symbol each side survives; a +s and -s of the
        SAME symbol cancel }
      if (p2 >= 0) and (m >= 0) and (p2 = m) then begin p2 := -1; m := -1; end;
      if (m2 >= 0) and (p >= 0) and (m2 = p) then begin m2 := -1; p := -1; end;
      if p2 >= 0 then
      begin
        if p >= 0 then GasError('the sum of two symbols'' addresses: ' + GasEx);
        p := p2;
      end;
      if m2 >= 0 then
      begin
        if m >= 0 then GasError('two symbols subtracted: ' + GasEx);
        m := m2;
      end;
      { a difference already known in one section folds now }
      if (p >= 0) and (m >= 0) and (GasSymSec[p] >= 0) and (GasSymSec[p] = GasSymSec[m]) then
      begin
        c := c + GasSymVal[p] - GasSymVal[m];
        p := -1; m := -1;
      end;
    end
    else Break;
  end;
end;

procedure GasExpr(var c: Int64; var p, m: Integer);
begin
  GasExAdd(c, p, m);
end;

procedure GasEval(const s: AnsiString; var c: Int64; var p, m: Integer);
var saveEx: AnsiString; savePos: Integer;
begin
  saveEx := GasEx; savePos := GasExPos;
  GasEx := s;
  GasExPos := 1;
  GasExpr(c, p, m);
  GasExSkip;
  if GasExPos <= Length(GasEx) then GasError('trailing text in expression: ' + s);
  GasEx := saveEx; GasExPos := savePos;
end;

function GasEvalConst(const s: AnsiString): Int64;
var c: Int64; p, m: Integer;
begin
  GasEval(s, c, p, m);
  if (p >= 0) or (m >= 0) then GasError('a constant is needed here, not an address: ' + s);
  Result := c;
end;

{ ---- fixups ---- }

procedure GasAddFix(sec: Integer; pos: Int64; size, kind: Integer; c: Int64; p, m: Integer; insnEnd: Int64);
var k: Integer;
begin
  k := GasFixCount;
  Inc(GasFixCount);
  SetLength(GasFixSec, GasFixCount);
  SetLength(GasFixSize, GasFixCount);
  SetLength(GasFixKind, GasFixCount);
  SetLength(GasFixP, GasFixCount);
  SetLength(GasFixM, GasFixCount);
  SetLength(GasFixLine, GasFixCount);
  SetLength(GasFixPos, GasFixCount);
  SetLength(GasFixEnd, GasFixCount);
  SetLength(GasFixC, GasFixCount);
  GasFixSec[k] := sec;
  GasFixPos[k] := pos;
  GasFixSize[k] := size;
  GasFixKind[k] := kind;
  GasFixC[k] := c;
  GasFixP[k] := p;
  GasFixM[k] := m;
  GasFixEnd[k] := insnEnd;
  GasFixLine[k] := GasLineNo;
end;

{ A data value of n bytes: a constant now, or a fixup. }
procedure GasEmitValue(const s: AnsiString; n: Integer);
var c: Int64; p, m: Integer;
begin
  GasEval(s, c, p, m);
  if (p < 0) and (m < 0) then
  begin
    if (n < 8) and ((c >= (Int64(1) shl (8 * n))) or (c < -(Int64(1) shl (8 * n - 1)))) then
      GasError('value ' + s + ' does not fit in ' + AIntToStr(n) + ' bytes');
    GasEmitLE(c, n);
    Exit;
  end;
  if GasSecType[GasCur] = 8 then GasError('an address stored in a @nobits section');
  GasAddFix(GasCur, GasCurOff, n, GFK_ABS, c, p, m, 0);
  GasEmitLE(0, n);
end;

{ ---- strings ---- }

procedure GasEmitString(const s: AnsiString; zero: Boolean);
var i, v, k: Integer; t: AnsiString;
begin
  t := GasTrim(s);
  if (Length(t) < 2) or (t[1] <> '"') or (t[Length(t)] <> '"') then
    GasError('expected a "string": ' + s);
  i := 2;
  while i < Length(t) do
  begin
    if t[i] = '\' then
    begin
      Inc(i);
      case t[i] of
        'n': GasEmitByte(10);
        't': GasEmitByte(9);
        'r': GasEmitByte(13);
        'b': GasEmitByte(8);
        'f': GasEmitByte(12);
        '\': GasEmitByte(92);
        '"': GasEmitByte(34);
        'x', 'X':
          begin
            v := 0; k := 0;
            while (i + 1 < Length(t)) and (((t[i+1] >= '0') and (t[i+1] <= '9')) or
                  ((GasLowerCh(t[i+1]) >= 'a') and (GasLowerCh(t[i+1]) <= 'f'))) do
            begin
              Inc(i);
              if t[i] <= '9' then v := v * 16 + Ord(t[i]) - 48
              else v := v * 16 + Ord(GasLowerCh(t[i])) - 87;
              Inc(k);
            end;
            GasEmitByte(v);
          end;
        '0', '1', '2', '3', '4', '5', '6', '7':
          begin
            v := Ord(t[i]) - 48; k := 1;
            while (k < 3) and (i + 1 < Length(t)) and (t[i+1] >= '0') and (t[i+1] <= '7') do
            begin
              Inc(i); v := v * 8 + Ord(t[i]) - 48; Inc(k);
            end;
            GasEmitByte(v);
          end;
      else
        GasEmitByte(Ord(t[i]));
      end;
    end
    else GasEmitByte(Ord(t[i]));
    Inc(i);
  end;
  if zero then GasEmitByte(0);
end;

{ ---- instructions ---- }

procedure GasLineStmt(const stmtIn: AnsiString); forward;

{ The bytes AttEncodeOne left in AsmBytes become this section's, with their
  placeholders turned into fixups. }
procedure GasTakeBytes(const what: AnsiString);
var i, j, k, n, pfx, found, base, ripPos: Integer; v: Int64; insnEnd: Int64; kind: Integer;
begin
  n := AsmBytesCount;
  if GasCode32 then
  begin
    pfx := 0;
    while (pfx < n) and ((AsmBytes[pfx] = $66) or (AsmBytes[pfx] = $F0) or (AsmBytes[pfx] = $F2) or
          (AsmBytes[pfx] = $F3) or (AsmBytes[pfx] = $2E) or (AsmBytes[pfx] = $36) or
          (AsmBytes[pfx] = $3E) or (AsmBytes[pfx] = $26) or (AsmBytes[pfx] = $64) or
          (AsmBytes[pfx] = $65)) do Inc(pfx);
    if (pfx < n) and (AsmBytes[pfx] = $67) then
      GasError('.code32: ' + what + ' encodes with an address-size prefix');
    if (pfx < n) and (AsmBytes[pfx] >= $40) and (AsmBytes[pfx] <= $4F) then
      GasError('.code32: ' + what + ' needs a REX prefix (a 64-bit operand or r8-r15),'
               + ' which 32-bit code cannot encode');
  end;
  { `sym(%rip)` was encoded as the absolute placeholder -- ModRM(mod=00,
    rm=100), SIB 0x25, disp32. Deleting the SIB byte and setting rm=101 makes
    the same instruction rip-relative, so every form that takes memory takes
    rip without the encoder knowing. }
  ripPos := -1;
  if GasHaveRip then
  begin
    v := GAS_PHR;
    for i := 2 to n - 4 do
      if (AsmBytes[i] = (v and $FF)) and (AsmBytes[i+1] = ((v shr 8) and $FF)) and
         (AsmBytes[i+2] = ((v shr 16) and $FF)) and (AsmBytes[i+3] = ((v shr 24) and $FF)) then
      begin
        if ripPos >= 0 then GasError(what + ': the rip operand appears twice in its encoding');
        ripPos := i;
      end;
    if (ripPos < 0) or (AsmBytes[ripPos - 1] <> $25) or ((AsmBytes[ripPos - 2] and $C7) <> $04) then
      GasError(what + ': internal: the rip operand did not encode as an absolute address');
    AsmBytes[ripPos - 2] := (AsmBytes[ripPos - 2] and $F8) or 5;
    for i := ripPos - 1 to n - 2 do AsmBytes[i] := AsmBytes[i + 1];
    Dec(n);
    Dec(ripPos);
    for j := 0 to 3 do AsmBytes[ripPos + j] := 0;
  end;
  base := Integer(GasCurOff);
  insnEnd := base + n;
  for k := 0 to GasPhCount - 1 do
  begin
    if k = 0 then v := GAS_PH0 else v := GAS_PH1;
    found := -1;
    for i := 0 to n - 4 do
      if (AsmBytes[i] = (v and $FF)) and (AsmBytes[i+1] = ((v shr 8) and $FF)) and
         (AsmBytes[i+2] = ((v shr 16) and $FF)) and (AsmBytes[i+3] = ((v shr 24) and $FF)) then
      begin
        if found >= 0 then GasError(what + ': an operand''s address appears twice in its encoding');
        found := i;
      end;
    if found < 0 then
      GasError(what + ': an operand names a symbol, but its field is narrower than 32 bits');
    for j := 0 to 3 do AsmBytes[found + j] := 0;
    if GasCode32 then kind := GFK_ABS else kind := GFK_ABS32S;
    GasAddFix(GasCur, base + found, 4, kind, GasPhC[k], GasPhP[k], GasPhM[k], insnEnd);
  end;
  if GasHaveRip then
    GasAddFix(GasCur, base + ripPos, 4, GFK_PC, GasRipC, GasRipP, GasRipM, insnEnd);
  AttFixCount := 0;
  for i := 0 to n - 1 do GasEmitByte(AsmBytes[i]);
end;

{ Rewrite one operand: a symbolic part becomes a placeholder (or the rip
  label form), a constant one its decimal value. }
function GasRewriteOperand(const opIn: AnsiString): AnsiString;
var op, disp, spec: AnsiString; i, depth, open: Integer; c: Int64; p, m: Integer;
begin
  op := GasTrim(opIn);
  Result := op;
  if op = '' then Exit;
  if op[1] = '%' then
  begin
    { a segment override `%fs:disp(...)` keeps its prefix; the rest is memory }
    i := Pos(':', op);
    if i = 0 then Exit;
    Result := Copy(op, 1, i) + GasRewriteOperand(Copy(op, i + 1, Length(op) - i));
    Exit;
  end;
  if op[1] = '$' then
  begin
    GasEval(Copy(op, 2, Length(op) - 1), c, p, m);
    if (p < 0) and (m < 0) then begin Result := '$' + AIntToStr(c); Exit; end;
    if GasPhCount >= 2 then GasError('more than two symbolic operands in one instruction');
    GasPhC[GasPhCount] := c; GasPhP[GasPhCount] := p; GasPhM[GasPhCount] := m;
    if GasPhCount = 0 then Result := '$' + AIntToStr(GAS_PH0) else Result := '$' + AIntToStr(GAS_PH1);
    Inc(GasPhCount);
    Exit;
  end;
  { memory: [disp] [( base-spec )] -- the LAST top-level ( ) is a base spec
    only when it starts with a register or a comma }
  spec := '';
  disp := op;
  if op[Length(op)] = ')' then
  begin
    depth := 0; open := 0;
    for i := Length(op) downto 1 do
    begin
      if op[i] = ')' then Inc(depth)
      else if op[i] = '(' then
      begin
        Dec(depth);
        if depth = 0 then begin open := i; Break; end;
      end;
    end;
    if open > 0 then
    begin
      spec := GasTrim(Copy(op, open + 1, Length(op) - open - 1));
      if (spec <> '') and ((spec[1] = '%') or (spec[1] = ',')) then
        disp := GasTrim(Copy(op, 1, open - 1))
      else
        spec := '';
    end;
  end;
  if spec <> '' then spec := '(' + spec + ')';
  if CaseEqual(spec, '(%rip)') then
  begin
    if GasCode32 then GasError('.code32 has no rip-relative addressing: ' + op);
    if GasHaveRip then GasError('two rip-relative operands in one instruction');
    if disp = '' then begin GasRipC := 0; GasRipP := -1; GasRipM := -1; end
    else GasEval(disp, GasRipC, GasRipP, GasRipM);
    GasHaveRip := True;
    Result := AIntToStr(GAS_PHR);
    Exit;
  end;
  if disp = '' then begin Result := spec; Exit; end;
  GasEval(disp, c, p, m);
  if (p < 0) and (m < 0) then
  begin
    Result := AIntToStr(c) + spec;
    Exit;
  end;
  if GasPhCount >= 2 then GasError('more than two symbolic operands in one instruction');
  GasPhC[GasPhCount] := c; GasPhP[GasPhCount] := p; GasPhM[GasPhCount] := m;
  if GasPhCount = 0 then Result := AIntToStr(GAS_PH0) + spec else Result := AIntToStr(GAS_PH1) + spec;
  Inc(GasPhCount);
end;

{ `.code32` moves to and from a control register name a 32-bit register;
  the encoder (rightly, for 64-bit code) wants the 64-bit name. 0F 20/22 have
  no REX.W either way, so for r0..r7 the bytes are the same: rename. }
function GasCode32CrOperand(const op: AnsiString): AnsiString;
var t: AnsiString;
begin
  t := GasLower(GasTrim(op));
  Result := op;
  if (Length(t) = 4) and (t[1] = '%') and (t[2] = 'e') then
    Result := '%r' + Copy(t, 3, 2);
end;

procedure GasEncodeGeneric(const mnIn, ops: AnsiString);
var text, mn, o: AnsiString; k, n: Integer; hasCr: Boolean;
begin
  GasPhCount := 0;
  GasHaveRip := False;
  mn := mnIn;
  n := GasSplitCount(ops);
  hasCr := False;
  if GasCode32 then
    for k := 0 to n - 1 do
      if GasStartsWith(GasLower(GasSplitItem(ops, k)), '%cr') then hasCr := True;
  if hasCr and ((GasLower(mn) = 'movl') or (GasLower(mn) = 'mov')) then mn := 'mov';
  text := mn;
  for k := 0 to n - 1 do
  begin
    if k = 0 then text := text + ' ' else text := text + ', ';
    o := GasSplitItem(ops, k);
    if hasCr then o := GasCode32CrOperand(o);
    text := text + GasRewriteOperand(o);
  end;
  CurTok.Line := GasLineNo;   { errors raised inside the AT&T reader name this line }
  AttSrc := text;
  AttPos := 1;
  AttExtended := False;
  AttMaxOpnd := -1;
  AttInstrOrd := 0;
  AttLblCount := 0;
  AttFixCount := 0;
  AsmRipFixPos := -1;
  AsmBytesCount := 0;
  AttGasMode := True;
  AttGasCode32 := GasCode32;
  AttEncodeOne;
  AttGasMode := False;
  AttGasCode32 := False;
  GasTakeBytes(mn + ' ' + ops);
end;

function GasRegNum64(const r: AnsiString; var num: Integer): Boolean;
var size: Integer; nm: AnsiString;
begin
  Result := False;
  nm := GasTrim(r);
  if (Length(nm) < 2) or (nm[1] <> '%') then Exit;
  nm := Copy(nm, 2, Length(nm) - 1);
  if not AsmRegNum(nm, num, size) then Exit;
  Result := size = 8;
end;

function GasJccCode(const mn: AnsiString): Integer;
begin
  Result := -1;
  if (Length(mn) >= 2) and (mn[1] = 'j') then
    Result := AsmCC(Copy(mn, 2, Length(mn) - 1));
end;

{ A branch target: an expression, or `*operand` for an indirect one. }
procedure GasBranch(const mn, ops: AnsiString);
var op: AnsiString; c: Int64; p, m, r, cc, kind: Integer; pos0: Int64; isCall, isJmp: Boolean;
begin
  op := GasTrim(ops);
  if GasSplitCount(op) <> 1 then GasError(mn + ' takes one operand');
  isCall := (mn = 'call') or (mn = 'callq') or (mn = 'calll');
  isJmp := (mn = 'jmp') or (mn = 'jmpq') or (mn = 'jmpl');
  if (op <> '') and (op[1] = '*') then
  begin
    if not (isCall or isJmp) then GasError(mn + ' cannot be indirect');
    op := GasTrim(Copy(op, 2, Length(op) - 1));
    if GasCode32 then GasError('.code32: an indirect ' + mn + ' is not supported');
    if not GasRegNum64(op, r) then GasError('an indirect ' + mn + ' through memory is not supported: ' + ops);
    if r >= 8 then GasEmitByte($41);
    GasEmitByte($FF);
    if isCall then GasEmitByte($D0 or (r and 7)) else GasEmitByte($E0 or (r and 7));
    Exit;
  end;
  GasEval(op, c, p, m);
  if m >= 0 then GasError(mn + ' to a difference of symbols');
  if p < 0 then GasError(mn + ' to an absolute address');
  if (mn = 'loop') or (mn = 'loopl') or (mn = 'loopq') or (mn = 'loope') or (mn = 'loopz') or
     (mn = 'loopne') or (mn = 'loopnz') or (mn = 'jecxz') or (mn = 'jrcxz') or (mn = 'jcxz') then
  begin
    if (mn = 'loop') or (mn = 'loopl') or (mn = 'loopq') then GasEmitByte($E2)
    else if (mn = 'loope') or (mn = 'loopz') then GasEmitByte($E1)
    else if (mn = 'loopne') or (mn = 'loopnz') then GasEmitByte($E0)
    else
    begin
      if (mn = 'jecxz') and not GasCode32 then GasEmitByte($67);
      if (mn = 'jrcxz') and GasCode32 then GasError('.code32 has no jrcxz');
      GasEmitByte($E3);
    end;
    pos0 := GasCurOff;
    GasEmitByte(0);
    GasAddFix(GasCur, pos0, 1, GFK_PC8, c, p, m, pos0 + 1);
    Exit;
  end;
  kind := GFK_PLT;
  if isCall then GasEmitByte($E8)
  else if isJmp then GasEmitByte($E9)
  else
  begin
    cc := GasJccCode(mn);
    if cc < 0 then GasError('unknown branch ' + mn);
    GasEmitByte($0F);
    GasEmitByte($80 or cc);
  end;
  pos0 := GasCurOff;
  GasEmitLE(0, 4);
  GasAddFix(GasCur, pos0, 4, kind, c, p, m, pos0 + 4);
end;

{ Instructions with no operands, by their bytes. asmenc knows a codegen-shaped
  subset; a kernel needs the rest, and a table is the honest form for them.
  A 48-prefixed one does not exist in 32-bit code. }
function GasZeroOp(const mn: AnsiString): Boolean;
var b: AnsiString; i: Integer;
begin
  b := '';
  if mn = 'cld' then b := #$FC else if mn = 'std' then b := #$FD
  else if mn = 'cli' then b := #$FA else if mn = 'sti' then b := #$FB
  else if mn = 'hlt' then b := #$F4 else if mn = 'nop' then b := #$90
  else if mn = 'pause' then b := #$F3#$90 else if mn = 'int3' then b := #$CC
  else if mn = 'clc' then b := #$F8 else if mn = 'stc' then b := #$F9 else if mn = 'cmc' then b := #$F5
  else if mn = 'leave' then b := #$C9 else if (mn = 'leaveq') or (mn = 'leavel') then b := #$C9
  else if mn = 'rdmsr' then b := #$0F#$32 else if mn = 'wrmsr' then b := #$0F#$30
  else if mn = 'rdtsc' then b := #$0F#$31 else if mn = 'rdtscp' then b := #$0F#$01#$F9
  else if mn = 'cpuid' then b := #$0F#$A2 else if mn = 'ud2' then b := #$0F#$0B
  else if mn = 'clts' then b := #$0F#$06 else if mn = 'wbinvd' then b := #$0F#$09
  else if mn = 'invd' then b := #$0F#$08
  else if mn = 'lfence' then b := #$0F#$AE#$E8 else if mn = 'mfence' then b := #$0F#$AE#$F0
  else if mn = 'sfence' then b := #$0F#$AE#$F8
  else if mn = 'swapgs' then b := #$0F#$01#$F8 else if mn = 'syscall' then b := #$0F#$05
  else if (mn = 'sysretq') then b := #$48#$0F#$07 else if (mn = 'sysretl') or (mn = 'sysret') then b := #$0F#$07
  else if (mn = 'sysexit') then b := #$0F#$35 else if (mn = 'sysenter') then b := #$0F#$34
  else if (mn = 'pushfq') or ((mn = 'pushf') and not GasCode32) then b := #$9C
  else if (mn = 'popfq') or ((mn = 'popf') and not GasCode32) then b := #$9D
  else if (mn = 'pushfl') or ((mn = 'pushf') and GasCode32) then b := #$9C
  else if (mn = 'popfl') or ((mn = 'popf') and GasCode32) then b := #$9D
  else if (mn = 'cltq') or (mn = 'cdqe') then b := #$48#$98 else if (mn = 'cqto') or (mn = 'cqo') then b := #$48#$99
  else if (mn = 'cltd') or (mn = 'cdq') then b := #$99 else if (mn = 'cwtl') or (mn = 'cwde') then b := #$98
  else if mn = 'xgetbv' then b := #$0F#$01#$D0 else if mn = 'fninit' then b := #$DB#$E3
  else if mn = 'movsb' then b := #$A4 else if mn = 'movsq' then b := #$48#$A5 else if mn = 'movsl' then b := #$A5
  else if mn = 'stosb' then b := #$AA else if mn = 'stosq' then b := #$48#$AB else if mn = 'stosl' then b := #$AB
  else if mn = 'lodsb' then b := #$AC else if mn = 'lodsq' then b := #$48#$AD
  else if mn = 'cmpsb' then b := #$A6 else if mn = 'scasb' then b := #$AE;
  Result := b <> '';
  if not Result then Exit;
  if GasCode32 and (b[1] = #$48) then GasError('.code32 has no ' + mn);
  if (not GasCode32) and ((mn = 'pushfl') or (mn = 'popfl')) then GasError('64-bit code has no ' + mn);
  for i := 1 to Length(b) do GasEmitByte(Ord(b[i]));
end;

procedure GasInstr(const mnIn, opsIn: AnsiString);
var mn, ops, a0, a1: AnsiString; r: Integer; sel: Int64;
begin
  mn := GasLower(mnIn);
  ops := GasTrim(opsIn);
  if (GasSecFlags[GasCur] and 4) = 0 then
    GasError('an instruction (' + mn + ') in ' + GasSecName[GasCur] + ', which is not code');
  { prefixes written as their own word }
  if (mn = 'lock') or (mn = 'rep') or (mn = 'repe') or (mn = 'repz') or
     (mn = 'repne') or (mn = 'repnz') then
  begin
    if mn = 'lock' then GasEmitByte($F0)
    else if (mn = 'repne') or (mn = 'repnz') then GasEmitByte($F2)
    else GasEmitByte($F3);
    if ops <> '' then GasLineStmt(ops);   { the prefixed instruction }
    Exit;
  end;
  if (mn = 'jmp') or (mn = 'jmpq') or (mn = 'jmpl') or (mn = 'call') or (mn = 'callq') or
     (mn = 'calll') or (GasJccCode(mn) >= 0) or (mn = 'loop') or (mn = 'loopl') or
     (mn = 'loopq') or (mn = 'loope') or (mn = 'loopz') or (mn = 'loopne') or
     (mn = 'loopnz') or (mn = 'jecxz') or (mn = 'jrcxz') then
  begin
    GasBranch(mn, ops);
    Exit;
  end;
  if (mn = 'ljmp') or (mn = 'ljmpl') or (mn = 'lcall') or (mn = 'lcalll') then
  begin
    if not GasCode32 then GasError(mn + ' $sel, $off exists only in 32-bit code (use lretq or an indirect ljmp)');
    if GasSplitCount(ops) <> 2 then GasError(mn + ' takes $selector, $offset');
    a0 := GasSplitItem(ops, 0); a1 := GasSplitItem(ops, 1);
    if (a0 = '') or (a0[1] <> '$') or (a1 = '') or (a1[1] <> '$') then
      GasError(mn + ' takes $selector, $offset');
    sel := GasEvalConst(Copy(a0, 2, Length(a0) - 1));
    if (mn = 'ljmp') or (mn = 'ljmpl') then GasEmitByte($EA) else GasEmitByte($9A);
    GasEmitValue(Copy(a1, 2, Length(a1) - 1), 4);
    GasEmitLE(sel, 2);
    Exit;
  end;
  if (mn = 'movabs') or (mn = 'movabsq') then
  begin
    if GasCode32 then GasError('.code32 has no movabs');
    if GasSplitCount(ops) <> 2 then GasError('movabs takes $value, %reg');
    a0 := GasSplitItem(ops, 0); a1 := GasSplitItem(ops, 1);
    if (a0 = '') or (a0[1] <> '$') or not GasRegNum64(a1, r) then
      GasError('movabs: only the $imm64, %reg64 form is supported: ' + ops);
    if r >= 8 then GasEmitByte($49) else GasEmitByte($48);
    GasEmitByte($B8 + (r and 7));
    GasEmitValue(Copy(a0, 2, Length(a0) - 1), 8);
    Exit;
  end;
  if (mn = 'ret') or (mn = 'retq') or (mn = 'retl') then
  begin
    if ops <> '' then
    begin
      GasEmitByte($C2);
      GasEmitLE(GasEvalConst(Copy(ops, 2, Length(ops) - 1)), 2);
    end
    else GasEmitByte($C3);
    Exit;
  end;
  if mn = 'iretq' then
  begin
    if GasCode32 then GasError('.code32 has no iretq');
    GasEmitByte($48); GasEmitByte($CF);
    Exit;
  end;
  if (mn = 'iret') or (mn = 'iretl') then begin GasEmitByte($CF); Exit; end;
  if (ops = '') and GasZeroOp(mn) then Exit;
  if (mn = 'lretq') then begin GasEmitByte($48); GasEmitByte($CB); Exit; end;
  if (mn = 'lret') or (mn = 'lretl') then begin GasEmitByte($CB); Exit; end;
  GasEncodeGeneric(mn, ops);
end;

{ ---- macros ---- }

function GasFindMacro(const nm: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to GasMacCount - 1 do
    if GasMacName[i] = nm then begin Result := i; Exit; end;
end;

{ The parameter list `a, b=1` or `a b=1` as one name per line. }
function GasParamName(const params: AnsiString; k: Integer; var defVal: AnsiString): AnsiString;
var i, n, st: Integer; s, item: AnsiString;
begin
  s := params;
  for i := 1 to Length(s) do if (s[i] = ',') or (s[i] = #9) then s[i] := ' ';
  n := 0; i := 1; item := '';
  Result := ''; defVal := '';
  while i <= Length(s) do
  begin
    while (i <= Length(s)) and (s[i] = ' ') do Inc(i);
    if i > Length(s) then Break;
    st := i;
    while (i <= Length(s)) and (s[i] <> ' ') do Inc(i);
    item := Copy(s, st, i - st);
    if n = k then
    begin
      st := Pos('=', item);
      if st > 0 then
      begin
        defVal := Copy(item, st + 1, Length(item) - st);
        item := Copy(item, 1, st - 1);
      end;
      st := Pos(':', item);     { `n:req` }
      if st > 0 then item := Copy(item, 1, st - 1);
      Result := item;
      Exit;
    end;
    Inc(n);
  end;
end;

function GasParamCount(const params: AnsiString): Integer;
var d: AnsiString; n: Integer;
begin
  n := 0;
  while GasParamName(params, n, d) <> '' do Inc(n);
  Result := n;
end;

{ Arguments: comma-separated, or blank-separated when there is no comma. }
function GasArg(const args: AnsiString; k: Integer; var present: Boolean): AnsiString;
var i, n, st: Integer; s: AnsiString;
begin
  present := False;
  Result := '';
  if Pos(',', args) > 0 then
  begin
    if k < GasSplitCount(args) then
    begin
      Result := GasSplitItem(args, k);
      present := True;
    end;
    Exit;
  end;
  s := args;
  n := 0; i := 1;
  while i <= Length(s) do
  begin
    while (i <= Length(s)) and ((s[i] = ' ') or (s[i] = #9)) do Inc(i);
    if i > Length(s) then Break;
    st := i;
    while (i <= Length(s)) and (s[i] <> ' ') and (s[i] <> #9) do Inc(i);
    if n = k then
    begin
      Result := Copy(s, st, i - st);
      present := True;
      Exit;
    end;
    Inc(n);
  end;
end;

procedure GasExpandMacro(mi: Integer; const args: AnsiString);
var body, nm, val, d, line, outText: AnsiString; i, j, k, np, best, bestLen: Integer; present: Boolean;
    names, vals: array of AnsiString;
begin
  Inc(GasDepth);
  if GasDepth > 100 then GasError('macro expansion nested over 100 deep: ' + GasMacName[mi]);
  np := GasParamCount(GasMacParams[mi]);
  SetLength(names, np);
  SetLength(vals, np);
  for k := 0 to np - 1 do
  begin
    names[k] := GasParamName(GasMacParams[mi], k, d);
    val := GasArg(args, k, present);
    if (not present) or (val = '') then val := d;
    vals[k] := val;
  end;
  Inc(GasMacCounter);
  body := GasMacBody[mi];
  outText := '';
  i := 1;
  while i <= Length(body) do
  begin
    if (body[i] = '\') and (i < Length(body)) then
    begin
      if body[i + 1] = '@' then
      begin
        outText := outText + AIntToStr(GasMacCounter - 1);
        i := i + 2;
        Continue;
      end;
      if (body[i + 1] = '(') and (i + 2 <= Length(body)) and (body[i + 2] = ')') then
      begin
        i := i + 3;
        Continue;
      end;
      best := -1; bestLen := 0;
      for k := 0 to np - 1 do
      begin
        nm := names[k];
        if (Length(nm) > bestLen) and (Copy(body, i + 1, Length(nm)) = nm) then
        begin
          best := k; bestLen := Length(nm);
        end;
      end;
      if best >= 0 then
      begin
        outText := outText + vals[best];
        i := i + 1 + bestLen;
        Continue;
      end;
    end;
    outText := outText + body[i];
    Inc(i);
  end;
  { run each line }
  j := 1;
  for i := 1 to Length(outText) + 1 do
    if (i > Length(outText)) or (outText[i] = #10) then
    begin
      line := Copy(outText, j, i - j);
      GasLineStmt(line);
      j := i + 1;
    end;
  Dec(GasDepth);
end;

{ ---- directives ---- }

procedure GasDirective(const dirIn, rest: AnsiString);
var dir, a, b, t, flags, typ: AnsiString; n, i, k: Integer; v, fill, cnt: Int64; haveF: Boolean;
begin
  dir := GasLower(dirIn);
  if (dir = '.text') or (dir = '.data') or (dir = '.bss') then
  begin
    if GasTrim(rest) <> '' then GasError(dir + ' with a subsection number is not supported');
    GasSwitchTo(dir, '', '', False);
    Exit;
  end;
  if dir = '.section' then
  begin
    a := GasSplitItem(rest, 0);
    if (a <> '') and (a[1] = '"') then a := Copy(a, 2, Length(a) - 2);
    flags := ''; typ := ''; haveF := False;
    if GasSplitCount(rest) >= 2 then
    begin
      b := GasSplitItem(rest, 1);
      if (Length(b) >= 2) and (b[1] = '"') then
      begin
        flags := Copy(b, 2, Length(b) - 2);
        haveF := True;
      end;
    end;
    if GasSplitCount(rest) >= 3 then
    begin
      t := GasSplitItem(rest, 2);
      if (t <> '') and ((t[1] = '@') or (t[1] = '%')) then typ := GasLower(Copy(t, 2, Length(t) - 1))
      else typ := GasLower(t);
    end;
    if a = '' then GasError('.section needs a name');
    GasSwitchTo(a, flags, typ, haveF);
    Exit;
  end;
  if dir = '.previous' then
  begin
    k := GasCur; GasCur := GasPrev; GasPrev := k;
    Exit;
  end;
  if dir = '.code32' then begin GasCode32 := True; Exit; end;
  if dir = '.code64' then begin GasCode32 := False; Exit; end;
  if dir = '.code16' then GasError('.code16 is not supported');
  if (dir = '.intel_syntax') then GasError('.intel_syntax is not supported; this frontend reads AT&T');
  if (dir = '.att_syntax') or (dir = '.file') or (dir = '.ident') or (dir = '.loc') or
     (dir = '.hidden') or (dir = '.protected') or (dir = '.internal') or (dir = '.size') or
     (dir = '.extern') or GasStartsWith(dir, '.cfi_') then Exit;
  if (dir = '.globl') or (dir = '.global') or (dir = '.weak') or (dir = '.local') then
  begin
    n := GasSplitCount(rest);
    for i := 0 to n - 1 do
    begin
      k := GasSym(GasSplitItem(rest, i));
      if dir = '.weak' then begin GasSymWeak[k] := True; GasSymGlobal[k] := True; end
      else if dir = '.local' then GasSymGlobal[k] := False
      else GasSymGlobal[k] := True;
    end;
    Exit;
  end;
  if dir = '.type' then
  begin
    k := GasSym(GasSplitItem(rest, 0));
    t := GasLower(GasSplitItem(rest, 1));
    if (t = '@function') or (t = '%function') or (t = 'function') then GasSymType[k] := 2
    else if (t = '@object') or (t = '%object') or (t = 'object') then GasSymType[k] := 1;
    Exit;
  end;
  if (dir = '.set') or (dir = '.equ') or (dir = '.equiv') then
  begin
    GasLineStmt(GasSplitItem(rest, 0) + ' = ' + Copy(rest, Pos(',', rest) + 1, Length(rest)));
    Exit;
  end;
  if (dir = '.byte') or (dir = '.word') or (dir = '.short') or (dir = '.hword') or (dir = '.2byte') or
     (dir = '.long') or (dir = '.int') or (dir = '.4byte') or (dir = '.quad') or (dir = '.8byte') then
  begin
    if (dir = '.byte') then k := 1
    else if (dir = '.word') or (dir = '.short') or (dir = '.hword') or (dir = '.2byte') then k := 2
    else if (dir = '.quad') or (dir = '.8byte') then k := 8
    else k := 4;
    n := GasSplitCount(rest);
    for i := 0 to n - 1 do GasEmitValue(GasSplitItem(rest, i), k);
    Exit;
  end;
  if (dir = '.ascii') or (dir = '.asciz') or (dir = '.string') then
  begin
    n := GasSplitCount(rest);
    for i := 0 to n - 1 do GasEmitString(GasSplitItem(rest, i), dir <> '.ascii');
    Exit;
  end;
  if (dir = '.skip') or (dir = '.space') or (dir = '.zero') then
  begin
    cnt := GasEvalConst(GasSplitItem(rest, 0));
    fill := 0;
    if (dir <> '.zero') and (GasSplitCount(rest) >= 2) then fill := GasEvalConst(GasSplitItem(rest, 1));
    if cnt < 0 then GasError(dir + ' of a negative size');
    GasEmitFill(cnt, Integer(fill));
    Exit;
  end;
  if dir = '.fill' then
  begin
    cnt := GasEvalConst(GasSplitItem(rest, 0));
    k := 1; v := 0;
    if GasSplitCount(rest) >= 2 then k := Integer(GasEvalConst(GasSplitItem(rest, 1)));
    if GasSplitCount(rest) >= 3 then v := GasEvalConst(GasSplitItem(rest, 2));
    if k > 8 then k := 8;
    while cnt > 0 do begin GasEmitLE(v, k); Dec(cnt); end;
    Exit;
  end;
  if (dir = '.balign') or (dir = '.p2align') or (dir = '.align') then
  begin
    v := GasEvalConst(GasSplitItem(rest, 0));
    if dir = '.p2align' then v := Int64(1) shl Integer(v);
    fill := 0; haveF := False;
    if (GasSplitCount(rest) >= 2) and (GasSplitItem(rest, 1) <> '') then
    begin
      fill := GasEvalConst(GasSplitItem(rest, 1));
      haveF := True;
    end;
    GasAlign(v, Integer(fill), haveF);
    Exit;
  end;
  if dir = '.org' then
  begin
    v := GasEvalConst(GasSplitItem(rest, 0));
    if v < GasCurOff then GasError('.org moves backwards');
    GasEmitFill(v - GasCurOff, 0);
    Exit;
  end;
  if dir = '.macro' then
  begin
    a := GasTrim(rest);
    i := 1;
    while (i <= Length(a)) and GasIsIdChar(a[i]) do Inc(i);
    b := Copy(a, 1, i - 1);
    if b = '' then GasError('.macro needs a name');
    k := GasFindMacro(b);
    if k < 0 then
    begin
      k := GasMacCount;
      Inc(GasMacCount);
      SetLength(GasMacName, GasMacCount);
      SetLength(GasMacParams, GasMacCount);
      SetLength(GasMacBody, GasMacCount);
    end;
    GasMacName[k] := b;
    GasMacParams[k] := GasTrim(Copy(a, i, Length(a) - i + 1));
    GasMacBody[k] := '';
    GasCollect := 1;
    GasCollectNest := 0;
    GasCollectBody := '';
    GasCollectIdx := k;
    Exit;
  end;
  if dir = '.rept' then
  begin
    GasReptCount := GasEvalConst(rest);
    GasCollect := 2;
    GasCollectNest := 0;
    GasCollectBody := '';
    Exit;
  end;
  if (dir = '.endm') or (dir = '.endr') then GasError(dir + ' without a matching block');
  GasError('directive ' + dir + ' is not supported');
end;

{ ---- one statement ---- }

procedure GasLineStmt(const stmtIn: AnsiString);
var s, w, rest, d: AnsiString; i, st, k: Integer; c: Int64; p, m: Integer; lw: AnsiString;
begin
  s := GasTrim(stmtIn);
  { collecting a .macro / .rept body: everything up to its end, raw }
  if GasCollect <> 0 then
  begin
    lw := GasLower(s);
    i := 1;
    while (i <= Length(lw)) and GasIsIdChar(lw[i]) do Inc(i);
    w := Copy(lw, 1, i - 1);
    if (w = '.macro') or (w = '.rept') or (w = '.irp') then Inc(GasCollectNest)
    else if ((w = '.endm') or (w = '.endr')) and (GasCollectNest > 0) then Dec(GasCollectNest)
    else if (GasCollect = 1) and (w = '.endm') then
    begin
      GasMacBody[GasCollectIdx] := GasCollectBody;
      GasCollect := 0;
      Exit;
    end
    else if (GasCollect = 2) and (w = '.endr') then
    begin
      GasCollect := 0;
      d := GasCollectBody;
      while GasReptCount > 0 do
      begin
        st := 1;
        for i := 1 to Length(d) + 1 do
          if (i > Length(d)) or (d[i] = #10) then
          begin
            GasLineStmt(Copy(d, st, i - st));
            st := i + 1;
          end;
        Dec(GasReptCount);
      end;
      Exit;
    end;
    GasCollectBody := GasCollectBody + stmtIn + #10;
    Exit;
  end;
  if s = '' then Exit;
  { labels: `name:` / `N:`, any number of them }
  while True do
  begin
    i := 1;
    while (i <= Length(s)) and GasIsIdChar(s[i]) do Inc(i);
    if (i > 1) and (i <= Length(s)) and (s[i] = ':') then
    begin
      w := Copy(s, 1, i - 1);
      if GasIsDigit(w[1]) then
      begin
        k := 0;
        for st := 1 to Length(w) do
        begin
          if not GasIsDigit(w[st]) then GasError('a label may not start with a digit: ' + w);
          k := k * 10 + Ord(w[st]) - 48;
        end;
        GasDefineNum(k);
      end
      else
        GasDefine(GasSym(w));
      s := GasTrim(Copy(s, i + 1, Length(s) - i));
      if s = '' then Exit;
    end
    else Break;
  end;
  { name = expr }
  i := 1;
  while (i <= Length(s)) and GasIsIdChar(s[i]) do Inc(i);
  w := Copy(s, 1, i - 1);
  rest := GasTrim(Copy(s, i, Length(s) - i + 1));
  if (w <> '') and (rest <> '') and (rest[1] = '=') and ((Length(rest) < 2) or (rest[2] <> '=')) then
  begin
    GasEval(Copy(rest, 2, Length(rest) - 1), c, p, m);
    k := GasSym(w);
    if (p < 0) and (m < 0) then
    begin
      GasSymSec[k] := -2;
      GasSymVal[k] := c;
    end
    else if (m < 0) and (p >= 0) and (GasSymSec[p] >= 0) then
    begin
      GasSymSec[k] := GasSymSec[p];
      GasSymVal[k] := GasSymVal[p] + c;
    end
    else GasError('an equate of an undefined or relocatable value: ' + s);
    Exit;
  end;
  if w = '' then GasError('cannot read: ' + s);
  if w[1] = '.' then begin GasDirective(w, rest); Exit; end;
  k := GasFindMacro(w);
  if k >= 0 then begin GasExpandMacro(k, rest); Exit; end;
  GasInstr(w, rest);
end;

{ ---- the source text ---- }

{ Strip comments: # to end of line (gas's x86 comment character) and /* */,
  outside strings; split at ; and newlines. Each statement keeps its line. }
procedure GasProcessText(const src: AnsiString);
var i, n: Integer; inStr, inBlock: Boolean; cur: AnsiString; ch: Char;
begin
  n := Length(src);
  GasLineNo := 1;
  cur := '';
  inStr := False; inBlock := False;
  i := 1;
  while i <= n do
  begin
    ch := src[i];
    if inBlock then
    begin
      if (ch = '*') and (i < n) and (src[i + 1] = '/') then begin inBlock := False; Inc(i); end
      else if ch = #10 then
      begin
        GasLineStmt(cur); cur := ''; Inc(GasLineNo);
      end;
      Inc(i);
      Continue;
    end;
    if inStr then
    begin
      cur := cur + ch;
      if (ch = '\') and (i < n) then begin cur := cur + src[i + 1]; Inc(i); end
      else if ch = '"' then inStr := False;
      Inc(i);
      Continue;
    end;
    if ch = '"' then begin inStr := True; cur := cur + ch; Inc(i); Continue; end;
    if (ch = '/') and (i < n) and (src[i + 1] = '*') then begin inBlock := True; i := i + 2; Continue; end;
    if ch = '#' then
    begin
      { a comment to the end of the line (also cpp's `# 12 "file"` markers) }
      while (i <= n) and (src[i] <> #10) do Inc(i);
      Continue;
    end;
    if (ch = ';') or (ch = #10) then
    begin
      GasLineStmt(cur);
      cur := '';
      if ch = #10 then Inc(GasLineNo);
      Inc(i);
      Continue;
    end;
    cur := cur + ch;
    Inc(i);
  end;
  GasLineStmt(cur);
  if GasCollect = 1 then GasError('.macro without .endm');
  if GasCollect = 2 then GasError('.rept without .endr');
end;

{ ---- fixups -> patches and relocations ---- }

var
  GasRelSec, GasRelType, GasRelSym: array of Integer;
  GasRelOff, GasRelAdd: array of Int64;
  GasRelCount: Integer;

procedure GasAddRel(sec: Integer; off: Int64; typ, sym: Integer; add: Int64);
var k: Integer;
begin
  k := GasRelCount;
  Inc(GasRelCount);
  SetLength(GasRelSec, GasRelCount);
  SetLength(GasRelType, GasRelCount);
  SetLength(GasRelSym, GasRelCount);
  SetLength(GasRelOff, GasRelCount);
  SetLength(GasRelAdd, GasRelCount);
  GasRelSec[k] := sec;
  GasRelOff[k] := off;
  GasRelType[k] := typ;
  GasRelSym[k] := sym;
  GasRelAdd[k] := add;
end;

{ The symbol a relocation names: a global or undefined symbol by itself, a
  local one through its SECTION (encoded as -(section+1)) plus its offset. }
procedure GasRelTarget(p: Integer; var sym: Integer; var add: Int64);
begin
  if (GasSymSec[p] >= 0) and not GasSymGlobal[p] then
  begin
    sym := -(GasSymSec[p] + 1);
    add := add + GasSymVal[p];
  end
  else
  begin
    sym := p;
    GasSymUsed[p] := True;
  end;
end;

procedure GasResolve;
var i, p, m, sym, typ: Integer; c, d, add: Int64;
begin
  for i := 0 to GasFixCount - 1 do
  begin
    GasLineNo := GasFixLine[i];
    c := GasFixC[i]; p := GasFixP[i]; m := GasFixM[i];
    if (p >= 0) and (GasSymSec[p] = -2) then begin c := c + GasSymVal[p]; p := -1; end;
    if (m >= 0) and (GasSymSec[m] = -2) then begin c := c - GasSymVal[m]; m := -1; end;
    if m >= 0 then
    begin
      if GasSymSec[m] < 0 then GasError('''' + GasSymName[m] + ''' is subtracted but never defined');
      if (p >= 0) and (GasSymSec[p] = GasSymSec[m]) then
      begin
        c := c + GasSymVal[p] - GasSymVal[m];
        p := -1; m := -1;
      end
      else if (p < 0) and ((GasFixKind[i] = GFK_PC) or (GasFixKind[i] = GFK_PLT)) and (GasSymSec[m] = GasFixSec[i]) then
        GasError('a pc-relative value minus a symbol is not supported')
      else
        GasError('a difference of symbols in different sections cannot be relocated');
    end;
    if (p >= 0) and (GasSymSec[p] = -1) and GasSymHidden[p] then
      GasError(GasSymName[p] + ': no label follows the reference');
    case GasFixKind[i] of
      GFK_PC, GFK_PLT, GFK_PC8:
        begin
          if p < 0 then
          begin
            if GasFixKind[i] = GFK_PC then
            begin
              GasPatch(GasFixSec[i], GasFixPos[i], c, 4);
              Continue;
            end;
            GasError('a branch to an absolute address');
          end;
          if (GasSymSec[p] = GasFixSec[i]) and not GasSymWeak[p] then
          begin
            d := GasSymVal[p] + c - GasFixEnd[i];
            if GasFixSize[i] = 1 then
            begin
              if (d < -128) or (d > 127) then GasError('a rel8 branch (loop/jecxz) out of range: ' + AIntToStr(d));
            end
            else if (d < -2147483648) or (d > 2147483647) then GasError('a branch out of range');
            GasPatch(GasFixSec[i], GasFixPos[i], d, GasFixSize[i]);
            Continue;
          end;
          if GasFixSize[i] = 1 then GasError('loop/jecxz reach only a label in the same section');
          add := c - (GasFixEnd[i] - GasFixPos[i]);
          GasRelTarget(p, sym, add);
          if GasFixKind[i] = GFK_PLT then typ := 4 else typ := 2;
          GasAddRel(GasFixSec[i], GasFixPos[i], typ, sym, add);
        end;
    else
      begin
        if p < 0 then
        begin
          GasPatch(GasFixSec[i], GasFixPos[i], c, GasFixSize[i]);
          Continue;
        end;
        add := c;
        GasRelTarget(p, sym, add);
        case GasFixSize[i] of
          8: typ := 1;
          4: if GasFixKind[i] = GFK_ABS32S then typ := 11 else typ := 10;
          2: typ := 12;
        else typ := 14;
        end;
        GasAddRel(GasFixSec[i], GasFixPos[i], typ, sym, add);
      end;
    end;
  end;
end;

{ ---- the object file ---- }

procedure GasPut(v: Int64; n: Integer);
var i: Integer;
begin
  if GasOutLen + n > Length(GasOut) then SetLength(GasOut, (GasOutLen + n) * 2 + 4096);
  for i := 0 to n - 1 do
  begin
    GasOut[GasOutLen] := Byte((v shr (8 * i)) and $FF);
    Inc(GasOutLen);
  end;
end;

procedure GasPutStr(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do GasPut(Ord(s[i]), 1);
end;

procedure GasPadTo(a: Integer);
begin
  while (GasOutLen mod a) <> 0 do GasPut(0, 1);
end;

procedure GasPutAt(off: Integer; v: Int64; n: Integer);
var i: Integer;
begin
  for i := 0 to n - 1 do GasOut[off + i] := Byte((v shr (8 * i)) and $FF);
end;

procedure GasWriteObject(const path: AnsiString);
var
  i, k, nSec, nRelSec, shIdx, symTabIdx, strTabIdx, shstrIdx, firstGlobal, nSyms: Integer;
  strtab, shstr: AnsiString;
  secOff, relOff, relCnt: array of Integer;
  secNameOff, relNameOff, relShIdx: array of Integer;
  symOff, strOff, shstrOff, shOff, symNameOff, bind, typ, shndx: Integer;
  strDataOff, shstrDataOff: Integer;
  symtabNames: array of Integer;
begin
  nSec := GasSecCount;
  SetLength(secOff, nSec);
  SetLength(relOff, nSec);
  SetLength(relCnt, nSec);
  SetLength(secNameOff, nSec);
  SetLength(relNameOff, nSec);
  SetLength(relShIdx, nSec);
  for k := 0 to nSec - 1 do relCnt[k] := 0;
  for i := 0 to GasRelCount - 1 do Inc(relCnt[GasRelSec[i]]);
  { section header indices: 1..nSec user sections, then one .rela per user
    section that has relocations, then .symtab .strtab .shstrtab }
  shIdx := nSec + 1;
  nRelSec := 0;
  for k := 0 to nSec - 1 do
    if relCnt[k] > 0 then
    begin
      relShIdx[k] := shIdx;
      Inc(shIdx);
      Inc(nRelSec);
    end
    else relShIdx[k] := 0;
  symTabIdx := shIdx; strTabIdx := shIdx + 1; shstrIdx := shIdx + 2;

  { symbol order: null, a section symbol per section, named locals, then globals }
  strtab := #0;
  nSyms := 1 + nSec;
  for i := 0 to GasSymCount - 1 do
  begin
    GasSymOut[i] := -1;
    if GasSymHidden[i] or (GasSymSec[i] = -2) then Continue;
    if (GasSymSec[i] >= 0) and not GasSymGlobal[i] then
    begin
      GasSymOut[i] := nSyms;
      Inc(nSyms);
    end;
  end;
  firstGlobal := nSyms;
  for i := 0 to GasSymCount - 1 do
  begin
    if GasSymHidden[i] or (GasSymSec[i] = -2) then Continue;
    if GasSymGlobal[i] or ((GasSymSec[i] = -1) and GasSymUsed[i]) then
    begin
      GasSymOut[i] := nSyms;
      Inc(nSyms);
    end;
  end;
  SetLength(symtabNames, GasSymCount);
  for i := 0 to GasSymCount - 1 do
    if GasSymOut[i] >= 0 then
    begin
      symtabNames[i] := Length(strtab);
      strtab := strtab + GasSymName[i] + #0;
    end;

  shstr := #0;
  for k := 0 to nSec - 1 do
  begin
    secNameOff[k] := Length(shstr);
    shstr := shstr + GasSecName[k] + #0;
  end;
  for k := 0 to nSec - 1 do
    if relCnt[k] > 0 then
    begin
      relNameOff[k] := Length(shstr);
      shstr := shstr + '.rela' + GasSecName[k] + #0;
    end;
  symNameOff := Length(shstr); shstr := shstr + '.symtab' + #0;
  strOff := Length(shstr); shstr := shstr + '.strtab' + #0;
  shstrOff := Length(shstr); shstr := shstr + '.shstrtab' + #0;

  GasOutLen := 0;
  SetLength(GasOut, 4096);
  { ELF header, patched at the end }
  GasPut($464C457F, 4); GasPut(2, 1); GasPut(1, 1); GasPut(1, 1); GasPut(0, 1);
  GasPut(0, 8);
  GasPut(1, 2);            { ET_REL }
  GasPut(62, 2);           { EM_X86_64 }
  GasPut(1, 4);
  GasPut(0, 8);            { entry }
  GasPut(0, 8);            { phoff }
  GasPut(0, 8);            { shoff, patched }
  GasPut(0, 4);            { flags }
  GasPut(64, 2); GasPut(0, 2); GasPut(0, 2);
  GasPut(64, 2);           { shentsize }
  GasPut(shstrIdx + 1, 2); { shnum }
  GasPut(shstrIdx, 2);     { shstrndx }

  for k := 0 to nSec - 1 do
  begin
    if GasSecAlign[k] > 1 then GasPadTo(GasSecAlign[k]);
    secOff[k] := GasOutLen;
    if GasSecType[k] <> 8 then GasPutStr(GasSecData[k]);
  end;
  for k := 0 to nSec - 1 do
    if relCnt[k] > 0 then
    begin
      GasPadTo(8);
      relOff[k] := GasOutLen;
      for i := 0 to GasRelCount - 1 do
        if GasRelSec[i] = k then
        begin
          GasPut(GasRelOff[i], 8);
          if GasRelSym[i] < 0 then shndx := 1 + (-GasRelSym[i] - 1)
          else shndx := GasSymOut[GasRelSym[i]];
          GasPut((Int64(shndx) shl 32) or GasRelType[i], 8);
          GasPut(GasRelAdd[i], 8);
        end;
    end;
  GasPadTo(8);
  symOff := GasOutLen;
  GasPut(0, 24);
  for k := 0 to nSec - 1 do
  begin
    GasPut(0, 4); GasPut(3, 1); GasPut(0, 1); GasPut(k + 1, 2); GasPut(0, 8); GasPut(0, 8);
  end;
  { locals first, then globals: two passes over the same order used above }
  for i := 0 to GasSymCount - 1 do
    if (GasSymOut[i] >= 0) and (GasSymOut[i] < firstGlobal) then
    begin
      GasPut(symtabNames[i], 4);
      GasPut(GasSymType[i], 1);  { STB_LOCAL }
      GasPut(0, 1);
      GasPut(GasSymSec[i] + 1, 2);
      GasPut(GasSymVal[i], 8);
      GasPut(0, 8);
    end;
  for i := 0 to GasSymCount - 1 do
    if GasSymOut[i] >= firstGlobal then
    begin
      if GasSymWeak[i] then bind := 2 else bind := 1;
      typ := GasSymType[i];
      GasPut(symtabNames[i], 4);
      GasPut((bind shl 4) or typ, 1);
      GasPut(0, 1);
      if GasSymSec[i] >= 0 then GasPut(GasSymSec[i] + 1, 2) else GasPut(0, 2);
      if GasSymSec[i] >= 0 then GasPut(GasSymVal[i], 8) else GasPut(0, 8);
      GasPut(0, 8);
    end;
  strDataOff := GasOutLen;
  GasPutStr(strtab);
  shstrDataOff := GasOutLen;
  GasPutStr(shstr);
  GasPadTo(8);
  shOff := GasOutLen;
  GasPutAt(40, shOff, 8);
  { section headers }
  GasPut(0, 64);
  for k := 0 to nSec - 1 do
  begin
    GasPut(secNameOff[k], 4); GasPut(GasSecType[k], 4); GasPut(GasSecFlags[k], 8);
    GasPut(0, 8); GasPut(secOff[k], 8);
    if GasSecType[k] = 8 then GasPut(GasSecSize[k], 8) else GasPut(Length(GasSecData[k]), 8);
    GasPut(0, 4); GasPut(0, 4); GasPut(GasSecAlign[k], 8); GasPut(0, 8);
  end;
  for k := 0 to nSec - 1 do
    if relCnt[k] > 0 then
    begin
      GasPut(relNameOff[k], 4); GasPut(4, 4); GasPut($40, 8);
      GasPut(0, 8); GasPut(relOff[k], 8); GasPut(Int64(relCnt[k]) * 24, 8);
      GasPut(symTabIdx, 4); GasPut(k + 1, 4); GasPut(8, 8); GasPut(24, 8);
    end;
  { .symtab .strtab .shstrtab }
  GasPut(symNameOff, 4); GasPut(2, 4); GasPut(0, 8); GasPut(0, 8); GasPut(symOff, 8);
  GasPut(Int64(nSyms) * 24, 8); GasPut(strTabIdx, 4); GasPut(firstGlobal, 4); GasPut(8, 8); GasPut(24, 8);
  GasPut(strOff, 4); GasPut(3, 4); GasPut(0, 8); GasPut(0, 8); GasPut(strDataOff, 8);
  GasPut(Length(strtab), 8); GasPut(0, 4); GasPut(0, 4); GasPut(1, 8); GasPut(0, 8);
  GasPut(shstrOff, 4); GasPut(3, 4); GasPut(0, 8); GasPut(0, 8); GasPut(shstrDataOff, 8);
  GasPut(Length(shstr), 8); GasPut(0, 4); GasPut(0, 4); GasPut(1, 8); GasPut(0, 8);
  ElfLnkOpen(path);
  ElfLnkWrite(GasOut, GasOutLen);
  ElfLnkClose(path);
end;

{ ---- the entry point ---- }

procedure GasAssemble(var src: AnsiString; const inPath, outPath, baseDir: AnsiString; useCpp: Boolean);
var i: Integer;
begin
  GasFile := inPath;
  GasSecCount := 0; GasSymCount := 0; GasNumCount := 0; GasFixCount := 0;
  GasMacCount := 0; GasMacCounter := 0; GasDepth := 0; GasCollect := 0;
  GasRelCount := 0; GasTmpCount := 0;
  for i := 0 to GAS_SYM_HASH - 1 do GasSymHead[i] := -1;
  GasCode32 := False;
  GasAddSec('.text', 1, 6);
  GasAddSec('.data', 1, 3);
  GasAddSec('.bss', 8, 3);
  GasCur := 0; GasPrev := 0;
  if useCpp then
  begin
{$ifdef PXX_NO_CFRONT}
    ErrorNoPos('a .S file needs the C preprocessor, and this compiler was built with PXX_NO_CFRONT');
{$else}
    CPAsmSource := True;
    CPreprocess(src, baseDir);
    CPAsmSource := False;
{$endif}
  end;
  GasProcessText(src);
  GasResolve;
  GasWriteObject(outPath);
end;
