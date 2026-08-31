unit unit_cabi_intra;
{ Wrappers taking and returning only Integer, so the Pascal<->C boundary is the
  trivial case and every interesting call happens INSIDE the C unit. }
interface
function IntraDblFirst(n: Integer): Integer;
function IntraIntFirst(n: Integer): Integer;
function IntraThreeInts: Integer;
function IntraTwoDbl: Integer;
function IntraFlt(n: Integer): Integer;
function IntraDblArgIntRet(n: Integer): Integer;
function IntraMix4: Integer;
function IntraEight: Integer;
function IntraPairSum: Integer;
implementation
uses './cabi_intra.c';
function IntraDblFirst(n: Integer): Integer;    begin IntraDblFirst := cee_intra_dbl_first(n); end;
function IntraIntFirst(n: Integer): Integer;    begin IntraIntFirst := cee_intra_int_first(n); end;
function IntraThreeInts: Integer;               begin IntraThreeInts := cee_intra_three_ints; end;
function IntraTwoDbl: Integer;                  begin IntraTwoDbl := cee_intra_two_dbl; end;
function IntraFlt(n: Integer): Integer;         begin IntraFlt := cee_intra_flt(n); end;
function IntraDblArgIntRet(n: Integer): Integer; begin IntraDblArgIntRet := cee_intra_dbl_arg_int_ret(n); end;
function IntraMix4: Integer;                    begin IntraMix4 := cee_intra_mix4; end;
function IntraEight: Integer;                   begin IntraEight := cee_intra_eight; end;
function IntraPairSum: Integer;                 begin IntraPairSum := cee_intra_pairsum; end;
end.
