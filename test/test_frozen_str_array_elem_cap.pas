{ `array[..] of string[N]` must clamp its element stores at N, whatever the
  array itself is — a variable, a record FIELD, a nested field, a field of an
  array-of-record, or a dynamic array.

  The record-field shapes did not. `r.a[0] := <too long>` copied the SOURCE
  length and wrote past the element, and because the neighbour of a field is
  the NEXT FIELD, an oversized store silently rewrote it: `tail` below read
  31353 instead of 12345. The clamp had exactly one arm — an AN_INDEX whose
  base is an AN_IDENT — so the identical store one level in fell through it.

  The four shapes that always worked (global, local, by-value param, function
  result) are the four anyone writes a test for, which is why this survived;
  the record field is the only shape where the capacity must cross TWO hops,
  string[N] -> array type -> field.

  bug-a-record-field-array-of-string-n-drops-the-element-capacity-and-corrupts-the-next-field }
program test_frozen_str_array_elem_cap;
type
  TA        = array[0..1] of string[8];
  TRPlain   = record s: string[8]; end;
  TRAlias   = record a: TA; end;
  TRInline  = record a: array[0..1] of string[8]; end;
  TRTail    = record a: array[0..1] of string[8]; tail: Integer; end;
  TInner    = record a: array[0..1] of string[8]; t1: Integer; end;
  TOuter    = record inner: TInner; t2: Integer; end;
  TArrOfRec = array[0..1] of TInner;
const LONG = 'abcdefghijklmnop';
var
  g: TA; lv: array[0..1] of string[8];
  rp: TRPlain; ra: TRAlias; ri: TRInline; rt: TRTail;
  o: TOuter; ar: TArrOfRec;
  dyn: array of string[8];

procedure ByVal(p: TA);
begin WriteLn('param    ', p[0], ' ', Length(p[0])); end;

function Ret: TA;
begin Ret[0] := LONG; Ret[1] := 'x'; end;

begin
  { the four shapes that always worked — kept so a fix here cannot regress them }
  g[0] := LONG;   WriteLn('global   ', g[0], ' ', Length(g[0]));
  lv[0] := LONG;  WriteLn('local    ', lv[0], ' ', Length(lv[0]));
  ByVal(g);
  WriteLn('return   ', Ret[0], ' ', Length(Ret[0]));

  { a plain frozen field, which was never the broken one }
  rp.s := LONG;   WriteLn('plainfld ', rp.s, ' ', Length(rp.s));

  { the record-field shapes that were silently unclamped }
  ra.a[0] := LONG;  WriteLn('aliasfld ', ra.a[0], ' ', Length(ra.a[0]));
  ri.a[0] := LONG;  WriteLn('inlinefld ', ri.a[0], ' ', Length(ri.a[0]));

  o.t2 := 111; o.inner.t1 := 222;
  o.inner.a[0] := LONG;
  WriteLn('nested   ', o.inner.a[0], ' ', Length(o.inner.a[0]));

  ar[1].t1 := 333;
  ar[0].a[0] := LONG;
  WriteLn('arrofrec ', ar[0].a[0], ' ', Length(ar[0].a[0]));

  SetLength(dyn, 2);
  dyn[0] := LONG;   WriteLn('dynarr   ', dyn[0], ' ', Length(dyn[0]));

  { the corruption itself: an oversized element store must not reach the
    NEIGHBOURING FIELD. tail is the assertion — it must still read 12345. }
  rt.tail := 12345;
  rt.a[1] := 'ZZZ';
  rt.a[0] := 'abcdefghijklmnopqrstuvwxyz';
  WriteLn('overrun  ', rt.a[0], ' ', Length(rt.a[0]));
  WriteLn('neighbour-elem  ', rt.a[1]);
  WriteLn('neighbour-field ', rt.tail);
  WriteLn('nested t1=', o.inner.t1, ' t2=', o.t2, ' arr t1=', ar[1].t1);
end.
