10 REM feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar
20 REM A .bas that pulls no unit gets a ZERO-byte per-thread variable area with
30 REM no flag, so __pxxTlsBlockSize is TLS_USER_FIRST_OFF (1152) and not 4224.
40 REM Unit-free BASIC: bss 37,632 -> 34,560, a flat -3,072. Added 2026-09-22.
50 REM
60 REM THIS FILE MUST NEVER CONTAIN THE WORD THAT TURNS THE ARM OFF, not even
70 REM in a REM, which is why the sentences here are phrased around it. The
80 REM decision is a TEXT scan over the whole source (the token array is empty
90 REM at the only moment the size may be chosen), so a comment mentioning the
100 REM keyword reserves the area and the test asserting the feature would have
110 REM disabled the feature. That is not hypothetical -- it already happened
120 REM once, to this row's Pascal sibling, and is recorded in the ticket.
130 REM
140 REM THE CONTROL IS A SEPARATE FILE AND THE PAIR IS THE POINT:
150 REM test_a_basic_program_with_a_unit_pays_the_full_threadvar_area.bas is
160 REM identical but for the one line that names a unit, and asserts 4224.
170 REM This row reds at 4224 if the arm is removed; that row reds at 1152 if
180 REM the arm stops looking at the source, which is the cheapest wrong
190 REM widening. Neither row alone catches both.
200 REM
210 REM READS THE SLOT DIRECTLY, WITH NO HELPER UNIT, and it has to: the NilPy
220 REM row borrows test/units/utlsblock.pas to read this number, and importing
230 REM anything here would switch off the very thing under test. BASIC
240 REM resolves __pxxTlsBlockSize as a bare identifier, which is the only
250 REM reason a direct assertion is available on this side at all -- otherwise
260 REM this would be a bss delta, and a bss delta moves for a dozen unrelated
270 REM reasons.
280 PRINT __pxxTlsBlockSize
