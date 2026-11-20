---
track: A
prio: 50
type: feature
status: done
owner: claude-dupwt
summary: "DUPLICATE, closed 2026-11-20: already delivered by 275ca726cc (2026-11-19, bug-a-an-unhandled-exception-prints-no-class-or-message-on-the-cross-backends) on i386/arm32/riscv32; ESP/xtensa prints it from PXXReportUnhandled."
---

# Unhandled exception detail line on i386, arm32, riscv32 and xtensa

x86-64 and aarch64 (since 2026-10-20) print
`Unhandled exception: <ClassName>: <Message>`. The other targets'
blocks in compiler/exception_emit.inc still print only "Unhandled exception".
Port the same guarded sequence. On the 32-bit targets the RTTI pointer sits at
vmt-4 and msg at obj+4, so the offsets need checking per target, not copying.
On ESP the line is what a serial console shows after a crash, which makes it
worth the most there.

## Closed 2026-11-20 (claude-dupwt): duplicate, already delivered

Re-measured at e45ee8e658: `raise EMine.Create('hello there')` prints
`Unhandled exception: EMine: hello there` on x86-64, i386, arm32 and riscv32
(qemu). The 32-bit blocks were ported by 275ca726cc (2026-11-19) under
[[bug-a-an-unhandled-exception-prints-no-class-or-message-on-the-cross-backends]].
On ESP (xtensa and the C3) the line comes from `PXXReportUnhandled` in
compiler/builtin/exceptions.pas, which WrapEspUnhandledReport installs around
the main body.

One correction to the text above, for whoever reads it: the 32-bit layout is
NOT "RTTI at vmt-4, msg at obj+4". It is blob = [vmt-8] (vmt-4 reads 0) and
msg at obj+8, with an 8-byte length prefix on both the frozen name and the
message string, the same as x86-64. Measured with a dump probe on all three
targets.
