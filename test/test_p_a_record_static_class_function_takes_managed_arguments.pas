{ A record's `class function ... static` called through the TYPE NAME, with
  MANAGED arguments.

  pxx called it with a by-value dummy Self that the method no longer has. Before
  `b0d53c73a` a record's static class function still carried a Self at parameter
  0, so the dummy lined the argument chain up with the parameter list; that
  commit removed the parameter and left this call site — which hand-rolls its
  own argument loop — still prepending the dummy. The chain was then one longer
  than the signature, and the lowering pairs by POSITION: the dummy took
  parameter 0 and every real argument took the parameter before its own.

  IT SHOWS UP ONLY IN THE MANAGED-ARGUMENT TEMP, which is why every unmanaged
  spelling stayed correct and nothing caught it. IR for `TP.Make('three')`
  against `Make(const b: AnsiString)`:

    pinned  const_int 0 tk=17 -> arg              the dummy, a pointer
            const_str -> store_sym tk=23 -> arg   the STRING gets the temp
    broken  const_int 0 tk=23 -> store_sym -> arg the DUMMY gets the temp
            const_str -> arg                      the string gets none

  So the callee read a length word behind a bare literal. Measured against
  fpc 3.2.2: one AnsiString argument gave Length = 1073741824, and a second
  argument of any kind after it segfaulted.

  EVERY ROW PRINTS ITS VALUES AND NONE IS ASSERTED ON AN EXIT CODE. Three of
  the eight spellings below exit 0 and print the wrong number; a harness that
  read `rc` would have reported them passing, and an earlier version of this
  matrix did exactly that — it printed a literal "ok" per row and so could only
  ever see the crashes. The `i` and `ii` rows CANNOT fail this bug (no managed
  argument, nothing to mistype) and are here as the other guard: they must keep
  printing the same values, because the fix removes an argument and a wrong fix
  would shift them.

  Found from a SEGFAULT in test_generic_nested_inline_specialize, three
  subsystems away — its `cross:` row is the only one carrying a managed field
  into a static factory. There are no generics in the defect at all.
  bug-p-a-record-static-class-function-is-called-with-a-dummy-self-it-no-longer-has }
program test_p_a_record_static_class_function_takes_managed_arguments;
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TI = record K, L: Integer;
    class function Make(const a: Integer): TI; static; end;
  TS = record K, L: Integer;
    class function Make(const b: AnsiString): TS; static; end;
  TIS = record K, L: Integer;
    class function Make(const a: Integer; const b: AnsiString): TIS; static; end;
  TSI = record K, L: Integer;
    class function Make(const b: AnsiString; const a: Integer): TSI; static; end;
  TSS = record K, L: Integer;
    class function Make(const b: AnsiString; const c: AnsiString): TSS; static; end;
  TII = record K, L: Integer;
    class function Make(const a: Integer; const d: Integer): TII; static; end;
  TIIS = record K, L: Integer;
    class function Make(const a: Integer; const d: Integer; const b: AnsiString): TIIS; static; end;
  TISI = record K, L: Integer;
    class function Make(const a: Integer; const b: AnsiString; const d: Integer): TISI; static; end;

class function TI.Make(const a: Integer): TI;
begin Result.K := a; Result.L := 0; end;
class function TS.Make(const b: AnsiString): TS;
begin Result.K := Length(b); Result.L := 0; end;
class function TIS.Make(const a: Integer; const b: AnsiString): TIS;
begin Result.K := a; Result.L := Length(b); end;
class function TSI.Make(const b: AnsiString; const a: Integer): TSI;
begin Result.K := Length(b); Result.L := a; end;
class function TSS.Make(const b: AnsiString; const c: AnsiString): TSS;
begin Result.K := Length(b); Result.L := Length(c); end;
class function TII.Make(const a: Integer; const d: Integer): TII;
begin Result.K := a; Result.L := d; end;
class function TIIS.Make(const a: Integer; const d: Integer; const b: AnsiString): TIIS;
begin Result.K := a + d; Result.L := Length(b); end;
class function TISI.Make(const a: Integer; const b: AnsiString; const d: Integer): TISI;
begin Result.K := a + d; Result.L := Length(b); end;

var
  vi: TI; vs: TS; vis: TIS; vsi: TSI; vss: TSS; vii: TII; viis: TIIS; visi: TISI;
begin
  vi   := TI.Make(3);                          WriteLn('i    ', vi.K,   '/', vi.L);
  vs   := TS.Make('three');                    WriteLn('s    ', vs.K,   '/', vs.L);
  vis  := TIS.Make(3, 'three');                WriteLn('is   ', vis.K,  '/', vis.L);
  vsi  := TSI.Make('three', 3);                WriteLn('si   ', vsi.K,  '/', vsi.L);
  vss  := TSS.Make('three', 'xy');             WriteLn('ss   ', vss.K,  '/', vss.L);
  vii  := TII.Make(3, 4);                      WriteLn('ii   ', vii.K,  '/', vii.L);
  viis := TIIS.Make(3, 4, 'three');            WriteLn('iis  ', viis.K, '/', viis.L);
  visi := TISI.Make(3, 'three', 4);            WriteLn('isi  ', visi.K, '/', visi.L);
end.
