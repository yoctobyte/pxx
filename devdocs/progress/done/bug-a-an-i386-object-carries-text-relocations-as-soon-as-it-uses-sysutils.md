---
type: bug
track: A
prio: 40
tags: [emit-obj, elf, i386, pic, rtl]
summary: "RESOLVED cd4af7824. 62 absolute .text relocations -> 0 for an i386 object whose program uses sysutils, and gcc -m32 -pie -Wl,-z,text goes from rc=2 to a running binary with no DT_TEXTREL. The family was an address used as an IMMEDIATE (, ) -- no register to borrow, so it reached neither the load nor the store conversion. Also fixed, found beside it and PRE-EXISTING: the --threadsafe i386 unlock stub's hand-counted  landed inside the store wrapper and returned to garbage."
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

Enumerated from the artefact as the ticket said to: 32  and 30 ,
nothing else. One family, and the reason it survived four landed conversions is
structural rather than accidental — the load conversion borrows the
instruction's own dead destination, the store conversion borrows a push/pop
scratch, and an **address used as an IMMEDIATE has neither**. The relocated
field is the immediate; the memory operand, where there is one, is a plain
register base, so nothing either function inspects is present.

The replacement builds the address on the stack and **touches no flags**. The
shorter  was written first and thrown away for
that reason:  and  write no flags, so making
their replacement write flags puts "never materialise a data address between a
 and its " on every future emitter, enforced by nothing. frankC
checked all thirteen sites and it holds today. That is exactly the shape of
correct-when-written that this repo keeps paying for.

Not done by sniffing the end of the code buffer, which is how the other
families are recognised:  is two bytes that 
also ends in when its displacement ends , and a ~13MB  makes
that reachable. Thirteen call sites carry the intent explicitly.

### Measured — both arms built to , shas asserted to differ

| | before  | after  |
| --- | --- | --- |
| i386  in ,  | 62 | **0** |
|  | rc=2, no binary | links, runs, no  |
| x86-64  object | — | **byte-identical** |
| i386  executable | — | **byte-identical** |

The two identity rows are the inertness claim and they are measurements: both
conversions are gated on , and the identical files come from
compilers whose shas differ.

Both new rows fail on the pre-fix binary — checked, not assumed. The count row
is 62 against a bound of 0, and it is paired with a **floor** on 
so "zero absolute" cannot pass on an object where nothing was emitted at all.

### A second, worse defect found beside it — and it was already there

The ticket's acceptance did not ask for this and it is the more dangerous half.
In , the I/O **unlock** stub's 
carried a hand-counted  over a span containing a global store — and under
 that store grows a /anchor/ wrapper. The jump landed on
the  INSIDE it:



The still-nested path popped the **caller's return address** into eax, stored
through it (a wild write to that address + 37563), and returned to garbage. The
object built clean; no relocation count, symbol table or link could see it.
Byte-identical under the pre-change compiler, so pre-existing.

All three jumps in those two stubs go through  now, which measures
the span after emitting it and refuses what does not fit. The 's "spin
block must be exactly 16 bytes" assert went with them — it existed only to pin
a literal.

**How it was found is the transferable part.** I asked frankC whether any rel8
span could contain one of MY thirteen sites. They answered no, and then named
the population I had not asked about: hand-written short jumps with literal
displacements, which never reach  at all. Their cross-reference
cleared my sites; checking the remainder found one that was already wrong. The
question I asked was about my change; the answer that mattered was about the
guard's coverage.

### Still open

Nothing from this ticket. The umbrella's remaining i386 line is now closed;
[[meta-a-pxx-produces-linkable-code]]'s  names the C-frontend
textrel ticket, which was already done.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 48aee7c68.
