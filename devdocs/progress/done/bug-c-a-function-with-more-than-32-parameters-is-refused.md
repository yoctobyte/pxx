---
title: "A function with more than 32 parameters was refused (MAX_PROC_PARAMS 32 -> 72)"
status: done
owner: claude-dupwt
prio: 70
area: core
---

amdgpu's display mode library has functions with up to 64 parameters
(CalculatePrefetchSchedule in display_mode_vba_30.c). pxx refused them: "more
than 32 parameters not supported (MAX_PROC_PARAMS)". That was 9 GPU-driver
compiles (feature-nodisx-linux-gpu-drivers-built-by-pxx).

MAX_PROC_PARAMS is now 72. The blocker recorded in
bug-a-max-proc-params-is-coupled-to-a-hardcoded-array-bound-by-a-comment is
gone: since bug-a-fourteen-compiler-internal-record-names-shadow-any-user-type
(2026-09-25), the builtin TProc layout sizes Params by MAX_PROC_PARAMS. So
TProc.Params in defs.inc is now `array[0..MAX_PROC_PARAMS-1]`, and a literal
there would now be the drift, laying the FPC seed out smaller. The wasm32
signature buffer (`ptypes`), which was sized 32, follows the constant too.

As symtab.inc predicts, a layout change converges in 2 self-host rounds.
Measured on plexus under load, self-compile of compiler.pas:
- 32 parameters: 51.5 s, max RSS 914,632 KB;
- 72 parameters: 45.4 s, max RSS 951,056 KB (+4%);
- the output binary is the same size.

Test row c_manyparm26: a 64-parameter mixed int/double function called
directly and through a pointer, a 70-parameter one, and structs by value
past the registers. Its expected output is gcc's.
