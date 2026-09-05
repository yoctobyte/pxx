program test_method_param_self_shift_family;
{$mode objfpc}
{ The implicit Self injected at parameter slot 0 shifts every per-param array
  with it. Four more were missing, found by asking the CONCEPT -- "which arrays
  are indexed by parameter slot?" -- and differencing the declared
  `array[0..MAX_PROC_PARAMS-1]` locals against what the shift loops carry.
  A census of any one array's CALLERS cannot find these: it returns only sites
  that already reached the helper, and the defect is a site that never did.

  Both rows below are asserted as a RELATION -- the method must agree with the
  byte-identical FREE routine -- so this file carries no per-target width and
  reads the same on every backend.

  Measured on pin fe1e9c37d322, so both pre-date the fix:

    pFixedLen / pFixedLo -- a named fixed-array parameter's element count and
      LOW BOUND. The method assigning arr[1..3] of an `array[1..3] of Integer`
      produced `0 10 20`, with the 30 landing PAST THE END of the array: a
      silent out-of-bounds write, no diagnostic. Free routine and fpc 3.2.2
      both give `10 20 30`.

    ptypesFileRecSize / ptypesFileElemTk -- a `file of T` parameter's element
      width and kind. With two file parameters of DIFFERENT record widths the
      first one inherits the second's, and the method body fails to COMPILE:
      "read/write(file): the variable is 4 bytes and the file's element type is
      20". Fail-closed rather than silent, and it needs two file parameters to
      show at all -- with one, both arms answer alike.
  bug-p-the-self-shift-forgets-puntyped-so-a-method-param-is-mislabelled }

type
  TA = array[1..3] of Integer;
  TSmall = record a: Integer; end;
  TBig   = record a, b, c, d, e: Integer; end;
  TFS = file of TSmall;
  TFB = file of TBig;

  TC = class
    constructor Make;
    { the Integer first, so a missing shift has somewhere to land }
    procedure WArr(n: Integer; var arr: TA);
    procedure WFiles(var s: TFS; var b: TFB);
  end;

constructor TC.Make; begin end;
procedure TC.WArr(n: Integer; var arr: TA);
begin arr[1] := 10; arr[2] := 20; arr[3] := 30; end;
procedure TC.WFiles(var s: TFS; var b: TFB);
var vs: TSmall; vb: TBig;
begin vs.a := 1; Write(s, vs); vb.a := 2; Write(b, vb); end;

procedure FreeArr(n: Integer; var arr: TA);
begin arr[1] := 10; arr[2] := 20; arr[3] := 30; end;
procedure FreeFiles(var s: TFS; var b: TFB);
var vs: TSmall; vb: TBig;
begin vs.a := 1; Write(s, vs); vb.a := 2; Write(b, vb); end;

var
  c: TC;
  a1, a2: TA;
  s: TFS; b: TFB;
  i, bad, fs1, fb1, fs2, fb2: Integer;
begin
  bad := 0;
  c := TC.Make;

  for i := 1 to 3 do begin a1[i] := 0; a2[i] := 0; end;
  FreeArr(7, a1);
  c.WArr(7, a2);
  for i := 1 to 3 do
    if a1[i] <> a2[i] then
      begin writeln('ARR slot ', i, ': free ', a1[i], ' method ', a2[i]); bad := bad + 1; end;
  { ...and the values, so a pair equal because BOTH are wrong still fails }
  if (a1[1] <> 10) or (a1[2] <> 20) or (a1[3] <> 30) then
    begin writeln('ARR free wrong: ', a1[1], ' ', a1[2], ' ', a1[3]); bad := bad + 1; end;

  Assign(s, 'selfshift_fs1.tmp'); Rewrite(s);
  Assign(b, 'selfshift_fb1.tmp'); Rewrite(b);
  FreeFiles(s, b); fs1 := FileSize(s); fb1 := FileSize(b);
  Close(s); Erase(s); Close(b); Erase(b);

  Assign(s, 'selfshift_fs2.tmp'); Rewrite(s);
  Assign(b, 'selfshift_fb2.tmp'); Rewrite(b);
  c.WFiles(s, b); fs2 := FileSize(s); fb2 := FileSize(b);
  Close(s); Erase(s); Close(b); Erase(b);

  if (fs1 <> fs2) or (fb1 <> fb2) then
    begin writeln('FILE free ', fs1, '/', fb1, ' method ', fs2, '/', fb2); bad := bad + 1; end;
  if (fs1 <> 1) or (fb1 <> 1) then
    begin writeln('FILE free wrong: ', fs1, '/', fb1); bad := bad + 1; end;

  if bad = 0 then writeln('SELFSHIFT OK') else writeln('SELFSHIFT FAILED ', bad);
end.
