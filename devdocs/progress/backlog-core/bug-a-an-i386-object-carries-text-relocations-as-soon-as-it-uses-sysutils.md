---
type: bug
track: A
prio: 40
tags: [emit-obj, elf, i386, pic, rtl]
summary: "An i386 --emit-obj object has 0 absolute .text relocations for a bare program and 62 for the same program with `uses sysutils`, so it cannot link into a hardened PIE. The existing green row asserting the Pascal i386 object is PIE-clean is measured on a fixture that uses no RTL unit, so it cannot see this."
status: open
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
