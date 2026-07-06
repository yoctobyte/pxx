10 REM regression: bug-basic-goto-gosub-halts-program
20 REM GOTO/GOSUB used to lex as tkHalt: program ENDED at the first jump,
30 REM exit 0, silently wrong. This exercises forward/backward GOTO, nested
40 REM GOSUB (shift-register return stack), and LET-less assignment.
50 PRINT "A"
60 GOTO 90
70 PRINT "SKIPPED"
90 PRINT "B"
100 I = 0
110 I = I + 1
120 IF I < 3 THEN GOTO 110
130 PRINT "looped ", I
140 GOSUB 300
150 PRINT "after gosub"
160 GOSUB 400
170 PRINT "done"
180 END
300 PRINT "sub1"
310 GOSUB 400
320 PRINT "sub1 back"
330 RETURN
400 PRINT "sub2"
410 RETURN
