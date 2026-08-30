---
prio: 45
track: A
status: backlog
owner: ""
---

# A hot write to a data page that shares with code costs 1600x under qemu

- **Type:** bug (Track A — ELF layout; file-owned by `compiler/elfwriter.inc`)
- **Found:** 2026-08-30 by frank-optimize-b4, chasing a Track T timeout on
  `test-threads#src:test/test_static_string_literals.pas@2`.
- **Not a codegen defect and not an aarch64 defect.** The same binary is fast
  natively and catastrophic under an emulator. It is an emulation artifact of a
  layout choice — but the test tiers run aarch64 under qemu, so it presents as
  a red tier.

## Measured

`test/test_static_string_literals.pas`, whose row 8 writes a static string
literal's refcount in a 200,000-iteration loop:

| binary | static blocks? | refcount word on a code page? | time |
| --- | --- | --- | --- |
| aarch64 -O0, under qemu-aarch64 | no | — | 1.193s |
| aarch64 -O3, under qemu-aarch64 | yes | **yes** | **99.083s** |
| x86-64 -O3, **native** | yes | yes | **0.009s** |
| x86-64 -O3, under qemu-x86_64 | yes | **yes** | **14.661s** |
| x86-64 -O2, under qemu-x86_64 | no (rc on the heap) | — | 0.435s |
| x86-64 -O3 **padded**, under qemu-x86_64 | yes | **no** | **0.118s** |

The last two rows are the controls that make it a mechanism rather than a
correlation. Removing the static blocks removes it; keeping the static blocks
and moving them **off** the shared page removes it too — and that build is the
*fastest* of the three, so the pass is not the problem.

The page arithmetic, read out of the binaries:

```
SLOW  (aarch64 -O3): 'recycled' rc word 0x420ea8 -> page 0x420000
                     highest proc     0x420710 -> page 0x420000   SAME
FAST  (+75 KB code): 'recycled' rc word 0x433418 -> page 0x433000
                     highest proc     0x42bc50 -> page 0x42b000   different
```

## Mechanism

`elfwriter.inc` emits **one PT_LOAD, RWX**, with the data section immediately
after the code. So the boundary page holds both. A qemu-user-style emulator
tracks which guest pages it has translated code from and invalidates those
translations when the guest writes to them — self-modifying-code detection. A
loop that writes a word on that page therefore re-translates the code on it,
every iteration.

Nothing writes to the data section in a hot loop *until* something puts a
mutable word there. `feature-opt-o3-static-string-literals`
([[bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython]]) does
exactly that: a string literal's managed block, refcount included, is built by
the compiler and lives in the data section. That is what armed it. It is not
what is wrong with it.

## Why it was hard to localise, and that part is reusable

Halving the test **exonerated both halves**:

| measured alone | -O0 | -O3 |
| --- | --- | --- |
| the 200,000-iteration loop row | 1.111s | **0.295s** |
| the other seven rows | 0.039s | **0.019s** |
| all eight together | 1.193s | **99.083s** |

Every part is faster at -O3 and the whole is 83x slower, because the thing that
varies is not a row: it is **an address**. Removing rows shrinks the code, which
moves the data, which moves the literal off the shared page. A bisect over rows
is structurally unable to see it, and each half reads as *exonerating* rather
than as inconclusive.

Also worth stating plainly: **the output is correct at every level and on every
target.** A correct-but-catastrophic result is invisible to every instrument
except a clock with a deadline on it, which is why this arrived as a tier
timeout and not as a bug.

## Two fixes, and they are not alternatives to each other

1. **Page-align the data section** (`elfwriter.inc`). One change, fixes it for
   every future write to `.data`, costs up to 4 KiB per binary. This is the
   general answer and the recommended one — the hazard is not specific to
   string literals, it is specific to *any* mutable word sharing a page with
   code, and the next one will be found the same expensive way.
2. **Stop writing to static literal blocks at all** — guard `PXXStrIncRef` /
   `PXXStrDecRef` (and x86-64's five hand-emitted retain/release sites) on a
   saturated-refcount floor, so a static block is never stored to. This is the
   better answer *for the pass*: it also deletes the `inc qword [rax-16]` from
   every literal site on x86-64 and the whole `PXXStrIncRef` CALL on aarch64,
   and it would let the blocks live in genuinely read-only memory later.
   Its failure mode is forgiving — a *missed* guard drifts a 2^30 refcount, a
   performance miss and not a correctness one — but it grows five hand-emitted
   x86-64 sequences, which is the `rel8` span hazard of
   [[bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows]] and must
   be checked for span, not only for semantics.

Not started. Filed rather than fixed because `elfwriter.inc` is held by
`feature-port-rtl-over-libc`, and because option 2 touches the hottest path in
the runtime and deserves its own sitting rather than the tail of another
ticket's session.

## Interim

`test_static_string_literals` now takes its loop count from `{$ifdef CPUX86_64}`
— 200,000 native, 2,000 emulated. This is not a workaround hiding the cliff:
the count was never part of what the row asserts (the static refcount starts at
2^30, so no reachable iteration count could prove the reference is taken), and
**all four arms produce byte-identical output against one expectation**, which
is the proof that the count is not being asserted. The cliff keeps its own
numbers here.
