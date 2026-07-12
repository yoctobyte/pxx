
## RESOLVED 2026-07-12 (ed106ab5) — not a coroutine bug: the canary constant

Root cause is shared by all 12 jobs in this family. `CO_CANARY = $C0DECAFE` in
lib/rtl/scheduler.pas is written and read through `PW = ^NativeInt` — SIGNED, and
32-bit on i386/arm32/riscv32 — so the high bit makes it sign-extend to a negative
on load. It only ever compared equal because the named constant was itself being
truncated to a 32-bit Integer. Commit 89366847 (a correct fix: constants above
MaxInt are now typed Int64) widened the comparison to 64 bits, and a perfectly
healthy stack started reading as clobbered -> Halt(217).

Fixed by keeping the guard below $80000000 ($4C0DECAF). `make test-i386` and
`make test-arm32` fully green.
