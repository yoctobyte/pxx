---
slug: bug-a-an-8-byte-by-value-record-loses-its-second-word-through-virtual-and-indirect-calls-on-every-32-bit-backend
track: A
prio: 65
type: bug
blocked-by: []
status: done
found: 2026-09-02
found-by: frankC
owner: frankC
summary: "FIXED in `567577507`. `Arg32Class` had no tyRecord case, so a by-value record classified as A32_WORD -- ONE word -- and the virtual and indirect ladders on every 32-bit backend passed half of an 8-byte record. Added the A32_RECORD band (<=4 bytes the word IS the record; 5..8 the callee slot is 8 bytes; >8 the frontend already sets IsRef so one word is an address) and routed all four backends through it. Verified on all SIX targets by test/test_byvalue_record_param_every_call_shape.pas: x86-64, i386, arm32, riscv32, aarch64 and xtensa all answer BYVALRECPARAM OK. Closed 2026-09-02 after re-running every target -- the fix landed and the ticket was never moved."
---

# An 8-byte by-value record loses its second word through virtual and indirect calls, on every 32-bit backend

Found while building the gate for
[[feature-a-i386-refuses-a-by-value-record-parameter-on-the-internal-convention-so-lib-rtl-image-does-not-build]].
That ticket is about i386 REFUSING a by-value record. Writing a test that covers
all three call shapes rather than only the direct one turned up something wider
and worse: three backends do not refuse, they get it wrong.

`test/test_byvalue_record_param_every_call_shape.pas`, at `995b1daef`:

```
x86-64   OK
aarch64  OK
i386     REFUSED  (only ordinal/pointer parameters supported yet)
arm32    FAILED   virtual 8-byte 7061 want 7035 | override 7601 want 7305 | indirect 7060 want 7035
riscv32  FAILED   virtual 8-byte 7059 want 7035 | override 7616 want 7305 | indirect 7060 want 7035
xtensa   FAILED   virtual 8-byte 7060 want 7035 | override 7616 want 7305 | indirect 7051 want 7035
```

Exit code 0 on all three. Nothing crashes.

## Cause, and it is one line missing in a shared oracle

`Arg32Class` (`compiler/symtab.inc`) classifies a by-value call argument for all
four 32-bit backends. Its ladder handles `tySet`, `tyInt64/tyUInt64`,
`tyDouble`, `tySingle` — and **not `tyRecord`**, which therefore falls through to
the `A32_WORD` default: one word.

`ParamValueSize` gives a by-value record a slot of `RecSize` rounded up to the
pointer size, so on a 32-bit target an 8-byte record's slot is EIGHT bytes and
the callee reads two words. The caller pushes one. The second word is whatever
was next on the stack.

That also explains the exact boundaries, and they are why this survived:

| record size | classified | slot | agrees? |
| --- | --- | --- | --- |
| 4 bytes | A32_WORD (1 word) | 4 | **yes, accidentally** |
| 5..8 bytes | A32_WORD (1 word) | 8 | **NO** |
| > 8 bytes | frontend sets IsRef, so one word = the address | 4 | yes |

So the defect is confined to a size band with a correct case on either side of
it, which is the shape that defeats a spot check.

## Why only virtual and indirect

Each backend's DIRECT call path has its own hand-rolled ladder that handles
records; only the virtual and indirect paths go through `Arg32Class`. This is
the third time that split has produced a bug — `ir_codegen386.inc` records the
by-value SET case arriving in one ladder and not the others, where
`pS(1, [eA,eC,eD], 9)` through a proc-var answered 838829819 instead of 139.

## What to build

Add `A32_RECORD` to `Arg32Class` and an emit arm to the virtual AND indirect
ladders of **all four** 32-bit backends. The arm is the one the SET case already
uses: the value register holds the record's ADDRESS, so push `ceil(RecSize/4)`
words from it, high first, so word 0 lands lowest.

**The comment at `ir_codegen386.inc:3936` argues against exactly this** — *"a new
class would silently reach two backends with no emit arm for it"* — and it was
right at the time. The answer is to write the arms, not to keep asking at one
site: the site-local question is what left the other three backends wrong.

Count the backends before closing. **Seven exist**; four are 32-bit and all four
are affected, i386 by refusal rather than by corruption.

## Gate

`test/test_byvalue_record_param_every_call_shape.pas` passing on all six
targets. It already discriminates: pre-fix x86-64 and aarch64 PASS, so a change
that merely makes everything green without those staying green has broken
something else.

## 2026-09-02 — closed after re-verifying, not from the commit log

Re-ran the guard on every runnable target at `c4ec910f5`, rather than closing on
the presence of a commit: x86-64, i386, arm32, riscv32, aarch64 and xtensa all
answer `BYVALRECPARAM OK`. `567577507` confirmed on origin/master with
`git merge-base --is-ancestor`, which asks about the branch rather than about
this checkout's object store.

Worth carrying from the fix: the test was written for the BOUNDARY (a row whose
word count differs from its argument count) rather than for the reported
failure, and that is what turned a ten-minute arm32 fix into four defects found
across four backends.
