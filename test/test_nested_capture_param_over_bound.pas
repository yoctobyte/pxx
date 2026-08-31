{ The UPPER half of the nested-capture parameter bound: 40 captures must still
  be REFUSED, and the refusal must NAME ITS NUMBERS.

  test_nested_capture_param_bound.pas pins that 20 captures are ACCEPTED (the
  literal-16 guard refused half the 32-wide space that exists, f8442bc59). Its
  header also states that 40 are still refused -- but nothing checked that, so
  the upper bound was a claim in a comment. Raising MAX_PROC_PARAMS, or dropping
  the guard entirely, would have gone unnoticed by every wired test. This file
  is that missing half.

  It also pins that the diagnostic PRINTS THE CAP AND THE COUNT. That is not
  cosmetic and it is the reason this file greps rather than merely expecting a
  nonzero exit. For as long as the bound was the literal 16, the message
  asserted a limit with NO VALUE in it -- and a limit you cannot check is a
  limit you can only accept. Whoever hit it counted their captures, got a number
  below whatever they would have guessed the cap was, and reshaped the routine;
  that code cannot be found from the compiler side afterwards. With the numbers
  printed, a reader capturing 17 things and told the max is 32 has a
  contradiction in front of them, and a wrong bound becomes a bug report instead
  of a workaround.

  Compile-fail test: it must NOT compile, and the message must carry both
  numbers. The Makefile greps for them. }
program test_nested_capture_param_over_bound;
procedure Outer;
var
  v0: Integer; v1: Integer; v2: Integer; v3: Integer; v4: Integer; v5: Integer; v6: Integer; v7: Integer; v8: Integer; v9: Integer; v10: Integer; v11: Integer; v12: Integer; v13: Integer; v14: Integer; v15: Integer; v16: Integer; v17: Integer; v18: Integer; v19: Integer; v20: Integer; v21: Integer; v22: Integer; v23: Integer; v24: Integer; v25: Integer; v26: Integer; v27: Integer; v28: Integer; v29: Integer; v30: Integer; v31: Integer; v32: Integer; v33: Integer; v34: Integer; v35: Integer; v36: Integer; v37: Integer; v38: Integer; v39: Integer;
  procedure Inner;
  begin
    v0 := 0;
    v1 := 1;
    v2 := 2;
    v3 := 3;
    v4 := 4;
    v5 := 5;
    v6 := 6;
    v7 := 7;
    v8 := 8;
    v9 := 9;
    v10 := 10;
    v11 := 11;
    v12 := 12;
    v13 := 13;
    v14 := 14;
    v15 := 15;
    v16 := 16;
    v17 := 17;
    v18 := 18;
    v19 := 19;
    v20 := 20;
    v21 := 21;
    v22 := 22;
    v23 := 23;
    v24 := 24;
    v25 := 25;
    v26 := 26;
    v27 := 27;
    v28 := 28;
    v29 := 29;
    v30 := 30;
    v31 := 31;
    v32 := 32;
    v33 := 33;
    v34 := 34;
    v35 := 35;
    v36 := 36;
    v37 := 37;
    v38 := 38;
    v39 := 39;
  end;
begin
  Inner;
  Writeln(v0);
end;
begin
  Outer;
end.
