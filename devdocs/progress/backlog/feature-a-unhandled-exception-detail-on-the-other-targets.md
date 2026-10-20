---
track: A
prio: 50
type: feature
---

# Unhandled exception detail line on i386, arm32, riscv32 and xtensa

x86-64 and aarch64 (since 2026-10-20) print
`Unhandled exception: <ClassName>: <Message>`. The other targets'
blocks in compiler/exception_emit.inc still print only "Unhandled exception".
Port the same guarded sequence. On the 32-bit targets the RTTI pointer sits at
vmt-4 and msg at obj+4, so the offsets need checking per target, not copying.
On ESP the line is what a serial console shows after a crash, which makes it
worth the most there.
