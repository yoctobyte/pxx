program test_arm32_record_byval_wide;
{ bug-arm32-record-byvalue-over-4-bytes-abi-gap: a plain (no var/const) by-value
  record param over 4 bytes (up to 8) silently dropped its high word on arm32 --
  three separate spots all only handled 4 bytes: IR_LOAD_SYM (loading the
  record's value from a named variable), the by-value call-arg push loop, and
  the callee's prologue param-spill. Fixing the word-count without also
  widening the param's own frame slot (compiler/symtab.inc AllocParam, which
  reserved only TARGET_PTR_SIZE for ANY record param) turned the data loss into
  active corruption of whatever param happened to sit next to it in the frame,
  so this covers both a lone record arg and records mixed among scalar params
  (before, at, and straddling the r0-r3/stack boundary). Output is identical on
  every target (oracle pattern). }

type
  TPlain = record a, b: integer; end;      { 8 bytes }
  TOdd   = record a: integer; b: byte; end; { rounds to 8 bytes }

procedure modPlain(r: TPlain);
begin
  r.a := 999; r.b := 888;   { local copy only -- must not leak to the caller }
end;

procedure lone(r: TPlain);
begin
  writeln(r.a, ' ', r.b);
end;

procedure mixedMiddle(x: integer; r: TPlain; y: integer);
begin
  writeln(x, ' ', r.a, ' ', r.b, ' ', y);
end;

procedure mixedTail(x1, x2, x3, x4: integer; r: TPlain);
begin
  writeln(x1, ' ', x2, ' ', x3, ' ', x4, ' ', r.a, ' ', r.b);
end;

procedure straddleStack(x1, x2, x3: integer; r: TPlain);
begin
  writeln(x1, ' ', x2, ' ', x3, ' ', r.a, ' ', r.b);
end;

procedure allOnStack(x1, x2, x3, x4, x5: integer; r: TPlain);
begin
  writeln(x1, ' ', x2, ' ', x3, ' ', x4, ' ', x5, ' ', r.a, ' ', r.b);
end;

procedure oddSize(r: TOdd);
begin
  writeln(r.a, ' ', r.b);
end;

var
  p: TPlain;
  o: TOdd;
begin
  p.a := 1; p.b := 2; lone(p);
  writeln(p.a, ' ', p.b);           { unchanged: by-value copy }

  p.a := 111; p.b := 222; modPlain(p);
  writeln(p.a, ' ', p.b);           { unchanged: modPlain's writes stay local }

  p.a := 7; p.b := 8;
  mixedMiddle(1, p, 2);
  mixedTail(1, 2, 3, 4, p);
  straddleStack(1, 2, 3, p);
  allOnStack(1, 2, 3, 4, 5, p);

  o.a := 200; o.b := 7;
  oddSize(o);

  writeln('done');
end.
