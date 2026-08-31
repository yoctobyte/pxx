program test_c_abi_intra_c_calls;
{ See test/cabi_intra.c for what this is and why it exists. In one line: the
  third cell of the table -- C caller to C callee with the C-ABI gate ON --
  which neither of the other two subjects can reach. }
uses unit_cabi_intra;
begin
  Writeln('dbl_first ',      IntraDblFirst(4));
  Writeln('int_first ',      IntraIntFirst(4));
  Writeln('three_ints ',     IntraThreeInts);
  Writeln('two_dbl ',        IntraTwoDbl);
  Writeln('flt ',            IntraFlt(4));
  Writeln('dbl_arg_int_ret ', IntraDblArgIntRet(4));
  Writeln('mix4 ',           IntraMix4);
  Writeln('eight ',          IntraEight);
  Writeln('pairsum ',        IntraPairSum);
end.
