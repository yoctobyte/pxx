program lib_math_exception_tree;
{ The FLOAT exception family descends from EMathError, the INTEGER one from
  EIntError, and the two trees are separate. Every row below was compared
  against fpc 3.2.2 -Mobjfpc and matches it exactly.

  ASSERTS RELATIONS, NOT NAMES OR WIDTHS, so it carries no per-target constant
  and means the same thing on every backend.

  THE TWO `FALSE` ROWS ARE THE TEST. A fix that simply reparented everything
  onto EMathError would satisfy all four TRUE rows and still be wrong: FPC keeps
  EDivByZero (integer) out of the math tree and EZeroDivide (float) out of the
  integer one. Found 2026-09-06 attempting uPSCompiler, which catches
  EZeroDivide and EMathError by name and stopped at `on: unknown exception
  class` -- EInvalidOp descended from Exception here, so `on E: EMathError`
  caught no float error at all. }
uses sysutils;
begin
  writeln('int-div-is-int   : ', EDivByZero.InheritsFrom(EIntError));
  writeln('int-div-not-math : ', EDivByZero.InheritsFrom(EMathError));
  writeln('invalidop-is-math: ', EInvalidOp.InheritsFrom(EMathError));
  writeln('zerodiv-is-math  : ', EZeroDivide.InheritsFrom(EMathError));
  writeln('overflow-is-math : ', EOverflow.InheritsFrom(EMathError));
  writeln('underflow-is-math: ', EUnderflow.InheritsFrom(EMathError));
  writeln('zerodiv-not-int  : ', EZeroDivide.InheritsFrom(EIntError));
  { The idiom the corpus target actually uses: catch any float error by its
    base. This is what the old tree could not do. }
  try
    raise EZeroDivide.Create('float divide by zero');
  except
    on E: EMathError do writeln('caught-by-base   : ', E.ClassName);
  end;
  { ...and the integer one must NOT be caught by that base. }
  try
    try
      raise EDivByZero.Create('integer divide by zero');
    except
      on E: EMathError do writeln('WRONG: EMathError caught an integer error');
    end;
  except
    on E: EIntError do writeln('int-escapes-math : ', E.ClassName);
  end;
  writeln('MATH-EXCEPTION-TREE OK');
end.
