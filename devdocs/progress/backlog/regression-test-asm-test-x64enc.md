
## RESOLVED 2026-08-30 (frankA) — self-inflicted, fixed in `658f4bea5`

Mine. `3a0ed43fb` routed `x64_syscall` through `EmitSyscall` so `--rtl-libc`
could reach the 17 mnemonic-spelled kernel entries. That worked for the compiler
and broke every other consumer of the file: this harness includes
`compiler/x64enc.inc` standalone, mocks the byte sink, and has no compiler
policy — so `EmitSyscall` was undefined at `x64enc.inc:193`.

The defect was a **layering inversion**, not a missing declaration: a byte
encoder had acquired an upward dependency on `RtlOverLibc`, `OptLevel` and the
call-site table. Adding a mock `EmitSyscall` to the harness would have turned it
green while leaving the encoder pointing the wrong way, so the next policy the
lowering needs breaks it again.

Fixed with a hook the encoder owns — `var X64SyscallHook: procedure = nil`, where
nil means "emit the two bytes". `compiler.pas` installs `@EmitSyscall`. No test
file changed.

Verified: this harness compiles and runs green, default codegen byte-identical
to a build of HEAD without the change, `--rtl-libc` unchanged (1 residual kernel
entry, div0 rc=200, SIGTERM rc=143).

**Note for the batch:** three of the five `test-asm` reds filed alongside this
one are NOT this defect — see
`regression-test-asm-test-asmcore-x64`. twatch files per source, so one cause
splits into several tickets; nothing stops two causes landing in one batch and
reading as one.
