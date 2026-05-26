10 REM ==================================================
20 REM   Comprehensive BASIC Test Suite (Frankenpile)
30 REM ==================================================

USES my_pas_lib
USES my_c_lib

40 LET X = 1
50 PRINT "--- Starting traditional GOTO / GOSUB loops ---"

60 IF X > 3 THEN GOTO 100
70 GOSUB 200
80 LET X = X + 1
90 GOTO 60

100 PRINT "--- Finished traditional jumps ---"
110 GOTO 300

200 REM Subroutine called via GOSUB
210 PRINT "In GOSUB subroutine: X =", X
220 RETURN

300 REM ==================================================
310 REM   Modern Numberless BASIC Segment
320 REM ==================================================

' Testing modern numberless FOR loop with STEP
PRINT "--- Starting FOR loop with STEP ---"
DIM i = 0
FOR i = 1 TO 10 STEP 2
  PRINT "FOR iteration i =", i
NEXT i

' Testing modern WHILE loop
PRINT "--- Starting WHILE loop ---"
DIM count = 5
WHILE count > 0
  PRINT "WHILE count =", count
  count = count - 1
WEND

' Testing cross-language imports
PRINT "--- Testing cross-language imports ---"
DIM mulRes = pascal_mul(6, 7)
PRINT "Imported Pascal function result (6 * 7) =", mulRes
DIM addRes = my_add(40, 2)
PRINT "Imported C function result (40 + 2) =", addRes

PRINT "--- Finished Comprehensive BASIC Test ---"
END
