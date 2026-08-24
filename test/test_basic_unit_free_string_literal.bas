REM A unit-free .bas program with a string literal.
REM
REM The whole property is that this COMPILES. With ApplyCallFixups present in
REM the BASIC driver -- which every other driver has -- it used to fail with
REM `unresolved forward: PXXStrFromLit`: the emitted AnsiString SHIMS were
REM emitted, but every shim's body is a builtinheap procedure and BASIC pulls
REM builtinheap through exactly one door, `USES`, which this program does not
REM open. Before the fixups pass existed here the call simply kept its
REM placeholder for the whole compile and (on x86-64) fell through -- a call
REM that silently did not happen.
REM
REM No USES on purpose. Adding one to this file destroys the test.
REM bug-a-a-unit-free-basic-program-calls-a-helper-it-never-emits
PRINT "unit-free"
10 PRINT "line numbered too"
