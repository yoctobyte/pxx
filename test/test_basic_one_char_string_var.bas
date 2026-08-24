REM A BASIC variable initialised from a ONE-CHARACTER string literal.
REM
REM `DIM m = "x"` then `PRINT m` printed 120 -- Ord('x') -- while
REM `DIM m = "hello"` printed hello and `PRINT "x"` written directly printed x.
REM The RHS comes from the shared Pascal expression parser, which tags 'x' as
REM tyChar and 'xy' as tyString, and both copies of BASIC's "what type is this
REM variable" rule tested for tyString alone, so a one-char initialiser fell
REM through to tyInteger.
REM
REM Both spellings are covered below, because the rule existed in two copies:
REM the DIM form and the LET-less `m = <expr>` form.
REM
REM NO string COMPARISON here, deliberately. `IF a = "x"` used to pass by
REM accident (120 = 120, an integer compare); now that these are strings it is
REM a real PXXStrEq call, whose body ships with builtinheap -- which a unit-free
REM .bas program never pulls -- so it is `compiler error: PXXStrEq not found` on
REM aarch64 and arm32. That is the same open class as
REM bug-a-basic-string-concat-in-a-unit-free-program-is-a-compiler-error and it
REM is tracked there; putting it in this test would only couple the two.
REM bug-a-basic-prints-a-string-variable-as-its-character-code
DIM a = "x"
DIM b = "hello"
c = "y"
DIM n = 5
PRINT a
PRINT b
PRINT c
PRINT n
