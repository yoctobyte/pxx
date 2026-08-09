{ A by-VALUE `set` or `string[N]` parameter gets its OWN COPY, like every other
  value parameter. It did not: the callee's `s := s + [7]` and `s := 'changed'`
  wrote straight through to the CALLER's variable — silently, no error — on
  x86-64, aarch64 and arm32. riscv32 already answered FPC's result, and that
  split is the per-backend "param slot holds a pointer" divergence table on
  bug-a-param-pointer-rule-divergence, which had concluded the divergence was
  LATENT after a probe that only READ the set.

  Every row below is diffed against FPC, including the ones that already
  agreed: var/out must keep writing back, const must keep aliasing (it cannot
  be written, so a copy would be pure cost), and a record CONTAINING a
  shortstring already copied correctly.
  bug-a-set-and-shortstring-value-params-alias-the-caller }
program test_set_shortstring_value_param_copies;

type
  TSet     = set of 0..31;
  TStr20   = string[20];
  TRecStr  = record s: TStr20; end;
  TRec     = record a: Integer; end;
  TFixed   = array[0..2] of Integer;

procedure MutSet(s: TSet);            begin s := s + [7]; end;
procedure MutStr(s: TStr20);          begin s := 'changed'; end;
procedure MutShort(s: ShortString);   begin s := 'changed'; end;
procedure MutRecStr(r: TRecStr);      begin r.s := 'changed'; end;
procedure MutRec(r: TRec);            begin r.a := 99; end;
procedure MutFixed(a: TFixed);        begin a[0] := 99; end;
procedure MutVar(v: Variant);         begin v := 99; end;

{ var/out must still write back }
procedure RefSet(var s: TSet);        begin s := s + [7]; end;
procedure RefStr(var s: TStr20);      begin s := 'changed'; end;

{ const is read-only, so it keeps aliasing — the escape hatch from the copy }
function ConstSet(const s: TSet): Boolean;   begin ConstSet := 3 in s; end;
function ConstStr(const s: TStr20): Integer; begin ConstStr := Length(s); end;

{ forwarding: the inner callee needs its own copy too }
procedure Inner(s: TStr20);           begin s := 'inner'; end;
procedure Outer(s: TStr20);           begin Inner(s); WriteLn('forwarded  : ', s); end;

var
  s: TSet; t: TStr20; sh: ShortString; rs: TRecStr; r: TRec; f: TFixed; v: Variant;
begin
  s := [3];       MutSet(s);
  if 7 in s then WriteLn('set value  : LEAK') else WriteLn('set value  : ok');
  t := 'orig';    MutStr(t);      WriteLn('str20 value: ', t);
  sh := 'orig';   MutShort(sh);   WriteLn('short value: ', sh);
  rs.s := 'orig'; MutRecStr(rs);  WriteLn('rec of str : ', rs.s);
  r.a := 1;       MutRec(r);      WriteLn('record     : ', r.a);
  f[0] := 1;      MutFixed(f);    WriteLn('fixed array: ', f[0]);
  v := 1;         MutVar(v);      WriteLn('variant    : ', v);

  s := [3];       RefSet(s);
  if 7 in s then WriteLn('var set    : ok') else WriteLn('var set    : LOST');
  t := 'orig';    RefStr(t);      WriteLn('var str20  : ', t);

  s := [3];       WriteLn('const set  : ', ConstSet(s));
  t := 'orig';    WriteLn('const str  : ', ConstStr(t));

  t := 'orig';    Outer(t);       WriteLn('after outer: ', t);
  WriteLn('SET SHORTSTRING VALUE PARAM OK');
end.
