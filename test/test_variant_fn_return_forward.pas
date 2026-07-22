program test_variant_fn_return_forward;
{ A Variant FUNCTION forwarding another Variant call's result
  (bug-a-variant-fn-return-forward-nrvo-corruption). `FuncName := call`
  leaves the LHS ASTTk unset, and the variant-target assign arm lacked the
  record arm's symbol-TypeKind fallback — the store fell to the generic
  8-byte store_sym, so the caller read VType garbage and a lost payload.
  Covers the bare-funcname, explicit-Result, and via-local forms, plus a
  string-valued variant so the ARC path is exercised. }
type
  PVRec = ^TVRec;
  TVRec = record VType, Payload: Int64; end;

function mk: Variant;
begin
  PVRec(@Result)^.VType := 2;
  PVRec(@Result)^.Payload := 77;
end;

function mkStr: Variant;
begin
  mkStr := 'forwarded';
end;

function relay: Variant;
begin
  relay := mk;
end;

function relayResult: Variant;
begin
  Result := mk;
end;

function relayLocal: Variant;
var x: Variant;
begin
  x := mk;
  relayLocal := x;
end;

function relayStr: Variant;
begin
  relayStr := mkStr;
end;

var t: Variant; s: AnsiString;
begin
  t := relay;
  writeln(PVRec(@t)^.VType, ' ', PVRec(@t)^.Payload);
  t := relayResult;
  writeln(PVRec(@t)^.VType, ' ', PVRec(@t)^.Payload);
  t := relayLocal;
  writeln(PVRec(@t)^.VType, ' ', PVRec(@t)^.Payload);
  s := relayStr;
  writeln(s);
end.
