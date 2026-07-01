program test_setlength_grow_capacity;
{ Regression for the inline AnsiString SetLength grow path (ir_codegen.inc).

  The grow-realloc branch must derive its geometric headroom from the string's
  LENGTH, not from the reused block's allocator capacity ([data-24]). PXXAlloc's
  free list is first-fit with no block splitting, so a short string can inherit a
  much larger freed block. If the grow then doubles that oversized *capacity*
  each step (old bug: `mov rcx,[rsi-24]; add rcx,rcx`), a string of length ~1
  explodes 4M -> 8M -> 16M -> ... -> OOM on every append while shared.

  Trigger: free a ~4 MiB block, let a 1-char string reuse it, then grow it while
  shared (refcount > 1 forces the realloc path). See
  devdocs/progress/done/bug-emitasmx64-heap-helpers-oom-selfhost.md. }
var
  big, t, u: AnsiString;
  i: Integer;
begin
  SetLength(big, 4000000);   { allocate a ~4 MiB block }
  big := '';                 { free it onto the allocator free list }

  t := 'a';                  { 1-char string; first-fit hands it the ~4 MiB block }
  for i := 1 to 100 do
  begin
    u := t;                  { share it: refcount > 1 -> grow takes the realloc path }
    SetLength(t, Length(t) + 1);
    t[Length(t)] := 'b';
    u := '';
  end;

  writeln('len=', Length(t));
  writeln('first=', t[1]);
  writeln('last=', t[Length(t)]);
  writeln('SETLENGTH_CAP_OK');
end.
