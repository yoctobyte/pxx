10 USES my_c_lib
20 REM feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar
30 REM THE CONTROL FOR test_a_unit_free_basic_program_pays_no_threadvar_area.bas,
40 REM and the two are a pair -- neither catches what the other does.
50 REM
60 REM A .bas that names a unit keeps the FULL 3,072-byte area, so
70 REM __pxxTlsBlockSize is 4224. Line 10 is the entire difference between the
80 REM two files and it is the only door BASIC has to a unit of any language
90 REM (bparser.inc's BSourceUsesAUnit says so in its own words).
100 REM
110 REM WHY THIS ROW EXISTS RATHER THAN BEING OBVIOUS. The unit it names is a C
120 REM unit on purpose. A NilPy arm of exactly this shape shipped and was
130 REM reverted on 2026-09-19 because NilPy reaches C units AMBIENTLY through
140 REM -Fu and every C unit declares a __thread errno, so a zero-byte area
150 REM refused every mixed build. BASIC is safe from that only because this
160 REM door is explicit -- so the day anything makes a unit arrive without the
170 REM source saying so, this row goes to 1152 and says which half broke.
180 REM
185 REM THE PINNED COMPILER IS NOT A CONTROL FOR THIS ROW AND IS FOR THE OTHER
186 REM ONE. Measured: the pin answers 4224 for BOTH files, so on the sibling
187 REM that is a real discriminator (HEAD answers 1152 there) and here it is
188 REM two compilers doing the same correct thing. Saying "the pin agrees"
189 REM about this row would be a guard that cannot fail, printing PASS.
190 REM Measured 2026-09-22 at 464ddd6c2b02: 4224 here, 1152 in the sibling.
200 REM It also builds and runs a real C unit, so a zero-byte area reaching a
210 REM __thread would refuse this compile outright rather than shipping a
220 REM wrong size: that failure is LOUD and names the flag (402d61e0d made it
230 REM a hard error; it was a warning before, which is what the stale comment
240 REM in ir_codegen.inc's NilPy block still describes).
250 PRINT __pxxTlsBlockSize
