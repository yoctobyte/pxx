---
track: A
prio: 50
type: feature
status: working
found: 2026-08-31
found-by: frankC
owner: frankA
blocked-by: []
summary: "A pxx x86-64 .o needs `-no-pie` to link, and modern toolchains default to PIE, so `gcc main.c mylib.o` fails with `relocation R_X86_64_32S against .bss can not be used when making a PIE object`. The cause is the BACKEND, not the writer: EmitDataRef emits an 8-byte absolute operand and EmitGlobRef a 4-byte sign-extended absolute displacement, so an object carries R_X86_64_64/R_X86_64_32S. The fix is a rip-relative global-reference form (R_X86_64_PC32), which changes instruction ENCODINGS and therefore lengths. MEASURED 2026-09-01 (frankA), see the census at the end: 854 of 1271 sites are a plain absolute [disp32] whose field ENDS the instruction (addend -4), 417 are `movabs $abs,%reg` that must become `lea %reg,[rip+disp32]`, and ZERO are indexed or carry a trailing immediate. The three byte-shapes preceding the relocated field are recognisable from what was just emitted, so this is a ONE-PLACE rewrite inside EmitGlobRef/EmitDataRef with a refusing guard, not ~200 call-site edits. The 'zero encoding change' alternative this ticket recommended pricing FIRST does not exist: a 64-bit absolute IMMEDIATE cannot be made position-independent by any relocation, so a third of the sites need an instruction rewrite either way -- frankC, who filed this, has accepted that correction. Do it unconditionally on x86-64, not under --emit-obj: a form emitted only under that flag is invisible to the self-host fixedpoint. Nothing is broken: -no-pie links and runs today under gcc, clang and tcc, and is documented in docs/reference/objects.md. Raise this when someone must link a pxx object into a PIE they do not control."
---

# x86-64 object output is position-dependent, so a link needs `-no-pie`

The general x86-64 object writer landed (41045d7b4). Its relocation model is
absolute, and that is a deliberate, stated choice rather than an oversight —
option (a) of the three the parent ticket set out. This is option (b).

## The symptom, exactly

```
$ pascal26 --emit-obj mylib.pas mylib.o
$ gcc main.c mylib.o -o prog
/usr/bin/ld: mylib.o: relocation R_X86_64_32S against `.bss' can not be used
             when making a PIE object; recompile with -fPIE
$ gcc -no-pie main.c mylib.o -o prog        # works
```

Measured 2026-08-31 with binutils ld, and the object links and runs correctly
under `gcc -no-pie`, `clang -no-pie` and `tcc`.

## Where it actually lives

Not in the writer. Two backend emitters decide it:

- `EmitDataRef` (`emit.inc`) — an 8-byte absolute data address, so
  `R_X86_64_64`.
- `EmitGlobRef` (`emit.inc`) — a 4-byte absolute global address. Every x86-64
  site is a `[disp32]` SIB form, which the CPU sign-extends, so `R_X86_64_32S`.

A linker can satisfy either only in a non-PIE link with everything below 2 GiB.

## The work

Teach the x86-64 backend a rip-relative global-reference form, selected under
`--emit-obj`, and emit `R_X86_64_PC32`. **The reason this is not a small
change** is that `[rip+disp32]` and `[disp32]` are different ModRM encodings of
different lengths, so switching form under a flag moves every subsequent code
offset — branch fixups, proc body addresses, DWARF ranges. It is backend work
with a real blast radius, which is why it was filed rather than bundled.

An alternative worth pricing first: keep the absolute form and emit a
`R_X86_64_64` GOT-style indirection for globals under `--emit-obj` only, the way
external calls already work (the operand names our own `.data` slot; the slot
carries the relocation). That costs a load per global reference in object output
only, and needs no encoding change at all.

## What it is NOT

Not a correctness bug — objects link and run today. Not a blocker for
`meta-a-pxx-produces-linkable-code`, whose measurement (a gcc-built caller
linking a pxx object) is satisfied by `-no-pie`.

## Umbrella

[[meta-a-pxx-produces-linkable-code]]

## Measured shape of the change — frankA, 2026-09-01

Not started as code. What follows is the census the implementation needs, taken
from the ARTEFACT rather than from reading the emitters, plus one correction to
this ticket's own recommendation.

### The instrument, and why its zeroes are worth anything

Every `.text` relocation site classified by **how many instruction bytes follow
the relocated field** — because that, not the mnemonic, is what sets a PC32
addend. Derived from instruction offsets, not from parsing mnemonics: a
mnemonic-shaped classifier puts `movl $imm, [abs]` in the same bucket as
`movabs $imm, reg`, and the first is exactly the case whose addend is not -4.

Validated against gcc, an oracle I did not write, in **both** directions:

| gcc-emitted instruction | trailing | my classifier | gcc's own addend |
| --- | --- | --- | --- |
| `movl $0x5,0x0(%rip)` | 4 | addend -8 | agrees |
| `mov %rdi,0x0(%rip)` | 0 | addend -4 | agrees |

**It caught its own bug before the number went out.** objdump WRAPS a long
instruction's byte column onto a continuation line that carries its own offset
prefix, so `movabs` sized as 7 bytes instead of 10 and 133 sites reported
`field crosses the instruction end`. That impossible-case branch was in as a
self-check; without it, a clean "0 trailing sites" would have shipped over a
broken length computation, and 0 is precisely the answer that looks like success.

### The census

1271 `.text` sites across 5 objects (161 + 111 of them in `test_emit_obj.o`):

| n | form | becomes |
| --- | --- | --- |
| 854 | `R_X86_64_32S`, field ends the instruction | `[rip+disp32]`, addend -4 |
| 417 | `R_X86_64_64`, `movabs $abs,%reg` | `lea %reg,[rip+disp32]` |
| **0** | trailing bytes after the field (addend not -4) | — |
| **0** | INDEXED (SIB with an index register) | — |

The two zeroes are the load-bearing ones and they are why this is tractable: no
site needs an `lea` scratch to survive losing its index register, and no site
needs a non-standard addend.

### The bytes before each field — this is what allows a ONE-PLACE fix

Read out of `.text` directly, for `test_emit_obj.o`:

| n | preceding bytes | form |
| --- | --- | --- |
| 154 | SIB `25`, ModRM mod=0 rm=4 | absolute `[disp32]` memory operand |
| 111 | `48 B8` / `48 BE` / `48 BF` | `movabs r64, imm64` |
| 7 | `B8+r` | `mov r32, imm32` (an address as a 32-bit immediate) |

Three shapes, all recognisable from the bytes already emitted. So the rewrite
does NOT need ~200 call-site edits: `EmitGlobRef`/`EmitDataRef` are called
immediately after the ModRM/SIB bytes, so they can rewrite what was just
emitted, in one place — drop the SIB and set rm=5 for the first shape, replace
the `movabs` with `lea` for the second.

**That peephole MUST refuse, loudly, on a fourth shape.** Three exist today; a
guard that silently passes an unrecognised one corrupts an instruction instead
of erroring. The refusal is the positive control, and the self-host build is
what would trip it.

**The hazard to check first:** `EncB` writes to `AsmBytes` instead of `Code`
when `EncToAsmBuffer` is set (`x64enc.inc`), and the inline-asm path defers
through `AsmRecordGlobalFixup`/`TAsmGlobFix` because AsmBytes offsets are not
final code positions. A peephole that looks back at `Code[CodeLen-1]` is wrong
in that path. The refusing guard covers it; do not assume it away.

### Correction to this ticket's recommended alternative

The ticket says to price "keep the absolute form, give globals a GOT-style
indirection under `--emit-obj` only... **zero encoding change**". That is not
achievable, and the measurement is why: **417 of 1271 sites are a 64-bit
absolute address loaded as an IMMEDIATE**, not a memory operand. No relocation
makes a `movabs $imm64` position-independent, and a GOT-slot indirection must
still replace it with a load. The slot itself then has to be reached from
`.text`, which is either another absolute displacement (the same problem) or a
rip-relative operand (the encoding change).

So the two options differ in degree, not in kind: **the encoding change is
unavoidable on a third of the sites either way.** frankC, who filed this, has
read the measurement and accepts the correction — their words: *"My ticket
oversells the alternative and you should trust your measurement over its
prose."*

### Do it unconditionally on x86-64, not under `--emit-obj`

A form emitted only under `--emit-obj` is invisible to `make compiler/pascal26`,
which builds an executable — CLAUDE.md's "the fixedpoint cannot see a construct
the compiler never writes", and this would be a construct the compiler never
writes in the gated path. Unconditional on x86-64 means the fixedpoint and the
whole suite exercise it on every build. It also shortens code (154 sites lose a
SIB byte, 417 go 10 bytes to 7), and it is a prerequisite the `.so` ticket needs
anyway.

### What this does NOT establish

The 1271 sites come from 5 objects, because `--emit-obj` correctly refuses a
program with no `cdecl` export and 115 of 120 sampled programs have none. The
two zeroes are therefore measured over a narrow corpus of emittable objects.
They should be re-run over whatever the implementation's own test corpus turns
out to be; the refusing peephole is what makes that safe rather than the census.
