{ ParamStr(i) with i > ParamCount -- the index is out of range and the answer
  must be the empty string.

  Reading ParamStr(1) before checking ParamCount is ordinary code, so this is
  not a hostile input. Run with NO arguments, and the two out-of-range indices
  below land on two DIFFERENT things, which is why both are here:

    index 1 = ParamCount+1  ->  argv[argc], the vector's NULL terminator
                                -> strlen(nil) -> SIGSEGV
    index 3                 ->  past the terminator into envp
                                -> a live environment string, printed as data

  Measured on the pre-fix compiler (pinned, 2026-08-31), same program, same
  runners, no arguments. x86-64 was already correct; the five cross backends
  scaled the index and added it to the argv base with no comparison against
  argc, and they do not all fail in the same place:

    x86-64   count=0 nil=0 lit=0  var=0  managed=0  nilmanaged=0 done
    i386     count=0 nil=SIGSEGV
    arm32    count=0 nil=SIGSEGV
    aarch64  count=0 nil=SIGSEGV
    riscv32  count=0 nil=0 lit=62 var=62 managed=62  then SIGSEGV
    xtensa   count=0 nil=0 lit=62 var=62 managed=62  then SIGSEGV

  The split is not noise. riscv32 and xtensa fill a frozen string through
  PXXCStrToFrozen, which already answers '' for a nil source -- so their `nil=`
  row was right for a reason unrelated to bounds, and only the envp rows and
  the managed path (its own inline strlen, no nil arm) fail. The other three
  emit the fill inline and crash on the first nil. A test that stopped at
  `nil=` would have called two targets clean while they leaked.

  62 was the length of the first environment variable at the time -- not a
  constant, just whatever the process happened to be holding.

  Both index SHAPES are here on purpose. `ParamStr(3)` is a literal and could
  one day be constant-folded; `ParamStr(n)` cannot be. Only the variable form
  was exercised on the managed path before, so a literal-only test would leave
  the constant arm of any future fold unguarded.

  And the three destinations are three code paths, not three spellings of one:
  expression position desugars to ArgStr(i, <hidden frozen temp>) via
  EmitArgvToString, a `string` destination goes through
  EmitArgvToStringManaged, and each bounds the index in its own emitter -- the
  managed one has to bound it BEFORE its inline strlen loop or it walks off nil.

  bug-a-argv-to-frozen-string-is-unchecked-on-four-untested-targets }
program test_paramstr_out_of_range;
var s: string; n: Integer;
begin
  WriteLn('count=', ParamCount);
  WriteLn('nil=', Length(ParamStr(ParamCount + 1)));
  WriteLn('lit=', Length(ParamStr(3)));
  n := 3;
  WriteLn('var=', Length(ParamStr(n)));
  ArgStr(n, s);
  WriteLn('managed=', Length(s));
  n := ParamCount + 1;
  ArgStr(n, s);
  WriteLn('nilmanaged=', Length(s));
  WriteLn('done');
end.
