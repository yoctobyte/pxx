---
slug: feature-c-fcf-protection-endbr64-and-the-gnu-property-note
track: C
prio: 20
type: feature
status: backlog
owner: unassigned
created: 2026-11-28
found-by: pxx2 (libffi's unix64.S/win64.S against gcc's build; pixx-cc asked for it on record)
tags: [cfront, codegen, gasfront, security, cet]
summary: "gcc on Ubuntu defaults to -fcf-protection: it predefines __CET__, puts endbr64 at every indirect-branch target (function entries, address-taken labels), marks indirect jumps through tables notrack, and writes a .note.gnu.property with X86_FEATURE_1_IBT|SHSTK. pxx does none of it. Its objects run correctly, but a link with pxx objects loses IBT/SHSTK for the whole program, and .S sources take their non-CET path (libffi picks 8-byte table entries). Wanted: -fcf-protection[=full|branch|return|none] with __CET__, endbr64 emission, and the property note in both the C backend and gasfront."
---

# -fcf-protection: endbr64 and the GNU property note

Measured on libffi 3.5.2. gcc's unix64.o and win64.o carry `endbr64` at
every entry and table slot, `notrack jmp *%r10`, and 16-byte jump-table
entries (`#ifdef __CET__`). pxx's carry none of these and use 8-byte
entries. Both are correct code. They differ only in CET.

What doing it means:

- `-fcf-protection` (and `=full|branch|return|none`) on the command line,
  predefining `__CET__` (1 branch, 2 return, 3 full) like gcc.
- The C backend: `endbr64` (F3 0F 1E FA) at each function entry that can be
  reached indirectly, and at address-taken labels / setjmp returns.
  `notrack` on switch-table jumps.
- The object: `.note.gnu.property` with GNU_PROPERTY_X86_FEATURE_1_AND
  (IBT=1, SHSTK=2), and only when every unit has it.
- gasfront: accept and pass through a source's own `.section
  .note.gnu.property` and `notrack`, and `endbr64` (it already encodes that).
- `pxx --link`: AND the property notes the way ld does.

Related: the OpenBSD BTCFI notes in
working/feature-port-libc-family-openbsd-netbsd-minix.md (same idea there,
with PT_OPENBSD_NOBTCFI as the opt-out).

Low priority. Nothing breaks without it. It's a hardening gap compared with
gcc's default output.
