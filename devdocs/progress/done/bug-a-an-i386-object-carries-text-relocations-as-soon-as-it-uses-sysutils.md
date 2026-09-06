---
type: bug
track: A
prio: 40
tags: [emit-obj, elf, i386, pic, rtl]
summary: "RESOLVED cd4af7824, AND THE `0` IS NOT A STABLE PROPERTY -- see the 2026-09-06 correction at the foot and [[bug-a-the-i386-pic-prefix-guard-reads-a-displacement-byte-as-a-prefix]]; test-emit-obj is red again at 1 relocation without any of this work regressing. 62 absolute .text relocations -> 0 for an i386 object whose program uses sysutils, and `gcc -m32 -pie -Wl,-z,text` goes from rc=2 to a running binary with no DT_TEXTREL. The family was an address used as an IMMEDIATE (`push imm32`, `mov [reg],imm32`) -- no register to borrow, so it reached neither the load nor the store conversion. Also fixed, found beside it and PRE-EXISTING: the --threadsafe i386 I/O unlock stub's hand-counted `jnz` landed inside the store family's wrapper, popped the caller's return address into eax, stored through it and returned to garbage."
status: done
owner: frankA
---

# An i386 object carries .text relocations as soon as it uses sysutils

## Measured

Identical program, one line different, `--emit-obj --target=i386`, counting
`R_386_32` in `.rel.text`:

```
program Mini;
[uses sysutils;]
var G: Integer = 1; cvar;
function mini_get: Integer; cdecl; begin mini_get := G; end;
begin end.
```

| `uses sysutils;` | R_386_32 in `.rel.text` |
| --- | --- |
| absent | **0** |
| present | **62** |

`ld` then warns `relocation in read-only section '.text'` on any link, and a
`-pie -Wl,-z,text` link would fail outright.

## Why the existing row does not catch it

`test-emit-obj` asserts *"the Pascal i386 .o links+runs as a hardened PIE too"*,
and that row is green. It is measured on `test/test_emit_obj.pas`, which uses
no RTL unit at all — a fixture whose count is 0 for reasons that have nothing to
do with the guarantee. The row is not wrong; its scope is one shape.

The C analogue was found and fixed
([[bug-a-an-i386-object-from-the-c-frontend-carries-text-relocations]]), so the
emitters the C path uses are already PC-relative. Whatever sysutils pulls in
reaches an absolute form the ticket above did not cover.

## Not caused by, but found beside, the data-symbol work

`d402147d6` is not involved: the count is 62 both with and without the `cvar`
directives on the same source, and 0 for a bare program that carries them. The
`cvar` marker was the control.

## First step

62 relocations is a small enough set to enumerate. `readelf -rW` gives the
offsets; `objdump -d` at those offsets names the shapes, and the count almost
certainly collapses to two or three emitters that never went through
`EmitGlobRef`/`EmitDataRef` — which is exactly how the C ticket's five
survivors were found. Enumerate from the artefact, not from the source.

## Acceptance

- A program with `uses sysutils` emits an i386 object with **0** `R_386_32` in
  `.rel.text`, asserted by count, not by a successful link.
- It links and runs under `gcc -m32 -pie -Wl,-z,text`, and the result carries no
  `DT_TEXTREL`.
- The existing PIE row keeps a fixture that uses an RTL unit, so its scope
  matches its wording.


## RESOLVED — cd4af7824

Enumerated from the artefact as the ticket said to: 32 `c7 00` and 30 `50 68`,
nothing else. One family, and the reason it survived four landed conversions is
structural rather than accidental — the load conversion borrows the
instruction's own dead destination, the store conversion borrows a push/pop
scratch, and an **address used as an IMMEDIATE has neither**. The relocated
field is the immediate; the memory operand, where there is one, is a plain
register base, so nothing either function inspects is present.

The replacement builds the address on the stack and **touches no flags**. The
shorter `call .L; add dword [esp], imm32` was written first and thrown away for
that reason: `push imm32` and `mov [reg], imm32` write no flags, so making
their replacement write flags puts *"never materialise a data address between a
cmp and its Jcc"* on every future emitter, enforced by nothing. frankC checked
all thirteen sites and it holds today. That is exactly the shape of
correct-when-written this repo keeps paying for.

Not done by sniffing the end of the code buffer, which is how the other
families are recognised: `c7 00` is two bytes that `mov [eax+disp32], imm32`
also ends in whenever its displacement ends `$00 $C7`, and a ~13MB `.data`
makes that reachable rather than theoretical. Thirteen call sites carry the
intent explicitly instead.

### Measured — both arms built to `converged`, shas asserted to differ

| | before `a4c67a5e6cc8` | after `aad81be5ae4e` |
| --- | --- | --- |
| i386 `R_386_32` in `.rel.text`, fixture with `uses sysutils` | 62 | **0** |
| `gcc -m32 -pie -Wl,-z,text` | rc=2, no binary | links, runs, no `DT_TEXTREL` |
| x86-64 `--emit-obj` object | — | **byte-identical** |
| i386 `--threadsafe` executable | — | **byte-identical** |

The two identity rows are the inertness claim and they are measurements, not
readings: both conversions are gated on `EmitObjMode`, and the two identical
files come from compilers whose shas differ.

Both new rows fail on the pre-fix binary — checked, not assumed. The count row
is 62 against a bound of 0, and it is paired with a **floor** on `R_386_PC32`
so "zero absolute" cannot pass on an object where nothing was emitted at all.
The unlock-stub row asserts its locator FOUND the stub before comparing
anything, because a disassembly search that matches nothing cannot fail.

### A second, worse defect found beside it — and it was already there

The acceptance did not ask for this and it is the more dangerous half. In
`--threadsafe --emit-obj --target=i386`, the I/O **unlock** stub's `jnz`
carried a hand-counted `+8` over a span containing a global store — and under
`--emit-obj` that store grows a push/anchor/pop wrapper. The jump landed on the
`pop` INSIDE it:

    23c: dec DWORD PTR ds:0x92c0
    242: jne 24c            <- meant to reach the ret at 254
    244: xor ecx,ecx
    246: push eax        }
    247: call .+0        }   the wrapper this span did not used to contain
    24c: pop  eax            <- lands here
    24d: mov [eax+0x92bb],ecx
    253: pop  eax
    254: ret

The still-nested path popped the **caller's return address** into eax, stored
through it — a wild write to that address plus 37563 — and returned to garbage.
The object built clean; no relocation count, symbol table or link could see it.
Byte-identical under the pre-change compiler, so pre-existing.

All three jumps in those two stubs go through `PatchRel8` now, which measures
the span after it is emitted and refuses what does not fit. The `je +16`'s
*"spin block must be exactly 16 bytes"* assert went with them: it existed only
to pin a literal, and a patched jump has nothing to pin.

**How it was found is the transferable part.** I asked frankC whether any rel8
span could contain one of MY thirteen sites. They answered no — and then named
the population I had not asked about: hand-written short jumps with literal
displacements, which never reach `CheckRel8` at all. Their cross-reference
cleared my sites; checking the remainder found one already wrong. The question
was about my change; the answer that mattered was about the guard's coverage.

### Still open

Nothing from this ticket. [[meta-a-pxx-produces-linkable-code]] listed i386
position independence as one of its two remaining gaps; that line is closed.

## CORRECTION 2026-09-06 (frankA) — the `0` was a measurement, not a property

`test-emit-obj` is red again, at **1** absolute `.text` relocation, and nothing
in this ticket regressed. The correction belongs here because this ticket's own
acceptance is what a reader will check against, and its first bullet —
*"emits an i386 object with **0** `R_386_32` in `.rel.text`"* — reads as an
invariant the fix established. It is not one.

The surviving relocation is in `PXXIoCheck`, and it is refused by the guard
rather than missed by an emitter:

    28f22:  8b 45 f0        mov  -0x10(%ebp),%eax
    28f25:  a3 b8 92 00 00  mov  %eax,0x92b8        <- R_386_32

`TryI386PcRelStore` handles `A3`. Its `I386PrefixBefore(CodeLen-1)` guard reads
the byte before the opcode — here the `f0` of the displacement `-0x10` — and
takes it for a LOCK prefix.

**The count is data-dependent, which is the part this ticket could not have
known and the next reader needs to.** One unrelated extra local in `PXXIoCheck`
moves `code` off `-0x10` and the count goes 1 -> 0; removing it restores the 1.
So 62 -> 0 was true at `cd4af7824` and is a fact about the frame offsets that
existed that day, not about position-independence. 46 commits have touched
`lib/rtl` since and one of them put a local at `-0x10` in a routine that stores
to a global.

Note the shape: this ticket's own resolution warns against recognising a family
by *"sniffing the end of the code buffer"* and lists thirteen call sites that
carry the intent explicitly for exactly that reason. The prefix guard is the
remaining sniffer, and it has now failed in the direction the resolution
predicted for the other one.

Diagnosed and filed, not fixed:
[[bug-a-the-i386-pic-prefix-guard-reads-a-displacement-byte-as-a-prefix]]. The
fix shape is the same one this ticket already argued for — announce from the
call site — and it is a wider change than it looks, because a missed
announcement turns a conservative refusal into a silent wrong-width access.

This ticket stays `done`. The work in it is correct and the acceptance was met
when it was measured; what is corrected is the claim that the number stays put.
