program test_dynarray_assign_to_a_var_parameter;
{ A whole-array assignment to a `var` / `out` DYNAMIC-ARRAY parameter must reach
  the caller. On x86-64 it did not: IR_STORE_SYM's dynarray arm read and wrote
  the frame slot directly, and for a by-ref param that slot holds the ADDRESS of
  the caller's handle rather than the handle — so every such assignment was
  silently discarded, in the callee and the caller alike.
  bug-a-a-whole-dynarray-assignment-to-a-var-parameter-is-discarded

  SetLength and element stores always worked (they route through IR_LEA, which
  has had the by-ref arm all along), which is exactly what made dynamic arrays
  through `var` look like they worked. Both are kept below as the control.

  Every row matches fpc 3.2.2. The five other backends were measured CORRECT
  before the fix and their emitted binaries are byte-identical after it, so this
  is a native-only defect with a cross-target test. }
{$mode objfpc}{$H+}
type
  TDA  = array of Integer;
  TDS  = array of AnsiString;
  TRec = record a: TDA; end;

procedure P_nil   (var d: TDA);                begin d := nil; end;
procedure P_asg   (var d: TDA; const e: TDA);  begin d := e; end;
procedure P_copy  (var d: TDA; const e: TDA);  begin d := Copy(e); end;
procedure P_out   (out d: TDA; const e: TDA);  begin d := e; end;
procedure P_ds    (var d: TDS; const e: TDS);  begin d := e; end;
function  F_ret(n: Integer): TDA;              begin SetLength(Result, n); end;
procedure P_fnres (var d: TDA);                begin d := F_ret(4); end;
{ controls — these always worked and must keep working }
procedure P_setlen(var d: TDA);                begin SetLength(d, 3); end;
procedure P_elem  (var d: TDA);                begin d[0] := 99; end;
procedure P_recfld(var r: TRec; const e: TDA); begin r.a := e; end;

var d, e: TDA; ds, es: TDS; r: TRec; i: Integer;
begin
  SetLength(e, 2);
  SetLength(d, 5); P_nil(d);       WriteLn('nil     ', Length(d));
  SetLength(d, 5); P_asg(d, e);    WriteLn('asg     ', Length(d));
  SetLength(d, 5); P_copy(d, e);   WriteLn('copy    ', Length(d));
  SetLength(d, 5); P_out(d, e);    WriteLn('out     ', Length(d));
  SetLength(d, 5); P_fnres(d);     WriteLn('fnres   ', Length(d));
  SetLength(ds, 5); SetLength(es, 2); P_ds(ds, es); WriteLn('dynstr  ', Length(ds));
  SetLength(d, 5); P_setlen(d);    WriteLn('setlen  ', Length(d));
  SetLength(d, 5); P_elem(d);      WriteLn('elem    ', d[0]);
  SetLength(r.a, 5); P_recfld(r, e); WriteLn('recfld  ', Length(r.a));

  { ARC: `e` must SURVIVE being assigned into d and d then nil'd. Without the
    retain this frees e's block while e still points at it — a use-after-free
    that prints nothing, so check the data, not just the length. }
  SetLength(e, 3); e[0] := 11; e[1] := 22; e[2] := 33;
  for i := 1 to 200 do
  begin
    SetLength(d, 5);
    P_asg(d, e);
    P_nil(d);
  end;
  WriteLn('survive ', Length(e), ' ', e[0], ' ', e[1], ' ', e[2]);
end.
