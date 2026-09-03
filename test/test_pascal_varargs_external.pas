{ A variadic C callee, reached from PASCAL — both faces of one concept.

  A C header imported with `uses` and a hand-written `external ...; varargs;`
  declaration are two spellings of the same fact, and until 2026-09-03 neither
  worked: the import produced `printf(Pointer)` and the directive was a hard
  PARSE ERROR ("expected 'begin' before 'varargs'"). Nothing was ever dropped on
  the import side — `ProcVariadic` has always been set by the C parser and four
  backends already honour it — the Pascal-side overload matcher simply never
  consulted it.

  ORACLE: fpc 3.2.2 compiles and runs this file unmodified, and every row below
  is identical there. That matters more than usual here, because `varargs` is
  FPC's own directive and the argument marshalling is the SysV C ABI, not ours
  to define.

  ROWS, and why each one can fail:
    - snprintf through a 6-argument call: asserts the VALUES the tail delivered
      (7/mid/9), not that it compiled. Mixed Integer and PChar in the tail.
    - a DOUBLE in the variadic tail: x86-64 SysV requires `al` to carry the
      count of vector registers used, and a callee reading a double the caller
      never announced gets garbage. 3.5 and 2.25 are exact in binary and are not
      values a zeroed register produces.
    - BOTH FPC directive orders, `cdecl; varargs; external` and `external;
      varargs`, because they are both in the wild and they arrive at different
      places in the parser.
    - the FIXED-PREFIX call, which worked BEFORE this change and is the row a
      regression would take away silently: a variadic callee invoked with no
      tail at all.
  bug-a-a-c-headers-variadic-tail-is-dropped-on-import }
program test_pascal_varargs_external;

{ sprintf and NOT snprintf, deliberately: snprintf's second parameter is a
  `size_t`, which is 64-bit on x86-64 and 32-bit everywhere else, so declaring
  it makes the TEST target-dependent -- and a QWord argument to a cdecl external
  SIGSEGVs on i386 and arm32 at the pin as well as at HEAD, which is a separate
  pre-existing defect this row must not be carrying. The buffer is 128 bytes and
  the longest row writes 15. }
function sprintf(buf: Pointer; fmt: PChar): Integer; cdecl; varargs; external 'libc.so.6';
function printf(fmt: PChar): Integer; cdecl; external 'libc.so.6'; varargs;
function fflush(f: Pointer): Integer; cdecl; external 'libc.so.6';

var
  b: array[0..127] of Char;
  n: Integer;
begin
  { printf FIRST, flushed immediately. pxx's writeln and libc's stdout are TWO
    buffers on one fd, so a printf left unflushed among the writelns lands
    wherever the flush happens -- FPC put it first and pxx last, with every
    VALUE identical. That is an ordering artefact of the two buffers and not an
    ABI difference; ordering it explicitly is what makes the row assertable. }
  printf(PChar('printf %d %s'#10), 42, PChar('tail'));
  fflush(nil);

  n := sprintf(@b[0], PChar('%d/%s/%d'), 7, PChar('mid'), 9);
  writeln('mixed n=', n, ' buf=', PChar(@b[0]));

  n := sprintf(@b[0], PChar('%.2f|%.2f'), 3.5, 2.25);
  writeln('double n=', n, ' buf=', PChar(@b[0]));

  n := sprintf(@b[0], PChar('%d %d %d %d %d %d %d %d'),
                1, 2, 3, 4, 5, 6, 7, 8);
  writeln('eight n=', n, ' buf=', PChar(@b[0]));

  { the fixed-prefix call: a variadic callee with NO tail }
  n := sprintf(@b[0], PChar('bare'));
  writeln('bare n=', n, ' buf=', PChar(@b[0]));
end.
