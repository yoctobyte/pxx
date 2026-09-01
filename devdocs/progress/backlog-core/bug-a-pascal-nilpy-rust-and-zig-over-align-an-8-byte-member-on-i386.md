---
track: A
prio: 45
type: bug
found: 2026-09-01
found-by: frankC
summary: "The C frontend's i386 struct layout was corrected to match gcc by routing member alignment through the new TypeFieldAlign (which caps a scalar at 4 on i386, as SysV requires); the Pascal, NilPy, Rust and Zig aggregate layouts still call TypeAlign and so still put an 8-byte member at offset 8 where every other i386 toolchain puts it at 4. Each is the same one-line substitution at a known line. It is filed rather than done because none of the four has a mixed-link oracle to prove the change, and a layout edit that is only self-consistently verified is exactly how the C bug survived."
---

# Pascal, NilPy, Rust and Zig over-align an 8-byte member on i386

`TypeFieldAlign` (`compiler/symtab.inc`) is the ABI-correct member alignment:
natural everywhere, capped at 4 on i386. It exists because a `double` inside a
struct aligns to 4 there — measured, `gcc -m32`, `struct MIX {int a; double y;}`
is sizeof 12 with `y` at 4.

Only `cparser.inc:13116` reads it. The other four frontends compute member
offsets from `TypeAlign`, which is now documented as the *storage* answer:

| frontend | lines | construct |
| --- | --- | --- |
| Pascal (P) | `pasparser_decl.inc` 3068, 3165, 3973, 5788 | `record` fields |
| NilPy (N) | `pyparser.inc` 33588, 33667, 33865, 34406, 34563 | struct/union fields |
| Rust (R) | `rparser.inc` 4537–4538, 4589–4590, 4651–4652, 4676–4677 | struct fields |
| Zig (Z) | `zparser.inc` 1622–1623 | struct fields |

`rparser.inc:447` (`RPayloadAlign`) is an enum PAYLOAD slot — storage, not a
member — and should keep calling `TypeAlign`. Check each site for which of the
two questions it is asking before substituting; that distinction is the whole
bug and one caller already looked like the other.

## Why this is not four one-line commits

**Each frontend's i386 layout is currently self-consistent, so no pxx-only test
can go either red or green on the change.** The C fix was provable only because
`test-c-abi-mixed-link` links a gcc translation unit against a pxx one and reads
the fields across the boundary. Nothing equivalent exists for the other four,
and `gcc -m32` is not an oracle for a Rust or Zig layout anyway — the oracle for
R is `rustc --target i686-unknown-linux-gnu` on a `#[repr(C)]` struct, for Z it
is `zig build-obj -target x86-i686-linux` on an `extern struct`, and neither
toolchain is on this box.

For **P and N** the question is not even settled: Pascal's `record` is not
required to match the C ABI unless it is `packed` or reached through a `cdecl`
boundary, so the change may be right only for the interop path. That is a Track
U question if it does not fall out of the first measurement.

**Do not do these as a batch.** The layout of a record is reachable by every
program in that language; the C change was worth its risk because a gate proved
it and because the C frontend's entire purpose is agreeing with C.

## What would make it cheap

An i386 mixed-link oracle per frontend, built the way the C one was: a pxx
object exporting a struct-valued function, a gcc `-m32` object reading the
fields, one link. For P that is achievable today — Pascal `cdecl` + gcc is
exactly the C gate's shape with the subject swapped.

Split off from [[bug-a-an-8-byte-scalar-is-over-aligned-inside-a-struct-on-i386]].
