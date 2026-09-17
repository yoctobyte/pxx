# Linking and ELF, mapped onto OUR code

**This is a MAP, not a tutorial: ~130 lines, about 2k tokens.** It exists so that
"read up on linking" means reading our own source instead of abstract theory,
because we already write ELF by hand and the code is the best textbook available
for it. Written 2026-09-17 at the owner's request.

**Do not read `compiler/elfwriter.inc` front to back — it is 6230 lines.** Every
pointer below names a procedure and a line, which is the point of the file.

## The one idea that unlocks the rest: ELF has TWO VIEWS of the same bytes

An ELF file is described twice, by two tables, over the same content.

- **The linking view — SECTIONS.** `.text`, `.data`, `.rodata`, `.bss`,
  `.symtab`, `.rela.text`. Fine-grained, named, and what a *linker* consumes.
- **The execution view — SEGMENTS.** A handful of `PT_LOAD` entries saying "map
  these bytes at this address with these permissions". Coarse, unnamed, and what
  the *kernel* consumes.

A `.o` has sections and no useful segments. An executable has both. Nearly every
confusing thing about linking is a consequence of that split — a linker's whole
job is to consume many section tables and produce one segment table.

## Read these three, in this order. Together they are under 400 lines

1. **`tools/pxxcrt_x86_64.S` — 76 lines.** The entry contract, and the best first
   read in the tree. It is the answer to "what actually happens before `main`":
   the kernel does not call `main`, it jumps to `_start` with the stack holding
   `argc`, `argv` and `envp`, and something has to marshal that. Normally that
   something is glibc's `crt1.o`. This file is our 76-line replacement.
2. **`compiler/elfwriter.inc:472-480`** — where we synthesise `_start` for an
   executable. Eight lines. Read it against (1) and the contract closes.
3. **`compiler/elfwriter.inc:497-575`** — the primitive writers: `writeU8`,
   `writeSym64`, `writeRela64`, `writeShdrA64`. Eighty lines that show an ELF
   file is a struct dump and nothing more mysterious than that.

## A RELOCATION IS A HOLE PLUS A RULE. That is the whole concept

When the compiler emits `call foo` and does not yet know where `foo` is, it
writes zeroes into the instruction and records: *"at offset X, patch in the
value of symbol `foo`, computed this way."* That record is a relocation. The
"computed this way" is the relocation TYPE.

Ours, and there are only six — `compiler/defs.inc`, `compiler/elfwriter.inc`:

| type | the rule |
| --- | --- |
| `R_X86_64_64` | write the symbol's absolute 64-bit address |
| `R_X86_64_PC32` | write the distance from here to the symbol (32-bit) |
| `R_X86_64_32S` | absolute address, signed 32-bit |
| `R_X86_64_PLT32` | distance to the symbol's PLT entry |
| `R_X86_64_RELATIVE` | dynamic: add the load base (for PIE/`.so`) |
| `R_X86_64_GLOB_DAT` | dynamic: fill a GOT slot with a symbol's address |

**Over the 400-object busybox build, pxx emits exactly two of them** —
`R_X86_64_PC32` (710066 times) and `R_X86_64_64` (13891). That number is why a
`pxx --link` for our own objects is a feature and not a project.

## Static and dynamic are two different machines, and we already own one

- **Static:** the linker resolves every symbol at build time and writes a
  finished image. Nothing is left to do at run time.
- **Dynamic:** the linker leaves a shopping list — `DT_NEEDED` entries naming
  libraries, a `.dynsym`, and dynamic relocations — and `ld.so` finishes the job
  at load time.

We already implement the PRODUCER side of both. `PrepareDynamicData`
(`elfwriter.inc:133`) builds the dynamic table; line 236 emits the `DT_NEEDED`
entries; line 314 documents the `dynsym` layout. **The interesting local
subtlety is at lines 157-167:** a library reached only by `weakexternal` imports
contributes NO `DT_NEEDED`, because emitting one would force the library to be
loaded in order to answer whether it is there — so a weak-only program collapses
back to a static link. That is a real design decision, written down, and it is a
good example of the kind of judgement linking is made of.

## Why a `.so` cannot be linked as if it were a `.o`

A `.so` has **already been through a link**. The information a static link needs
was consumed and discarded on the way:

- its relocations are DYNAMIC (`.rela.dyn`, `.rela.plt`) — instructions for
  `ld.so` at load time, not for a linker at build time;
- its symbols are in `.dynsym` (the export list); the `.symtab` and `.rela.text`
  a static link would need are usually stripped;
- it is position-independent and already laid out, so there is no per-function
  granularity left to pick from — you take the whole image or nothing;
- copy relocations, symbol interposition, version records and initialisation
  order across the `DT_NEEDED` chain are loader semantics with no static
  equivalent.

So the honest answer is: keep it dynamic (we support that), or get the `.a`.

## The part that is genuinely hard, if we ever consume gcc's objects

Not the relocation count — the **RELAXATIONS**. gcc emits `R_X86_64_GOTPCRELX`
and thread-local `GD` sequences *expecting the linker to rewrite the
instructions*: GOTPCRELX collapses to a direct `lea` when the symbol turns out
to be local, and TLS goes GD -> IE -> LE depending on what the final link is. A
linker that applies those relocations faithfully without relaxing them produces
slow code at best, and for TLS frequently something that does not work. Add
COMDAT section groups, archive (`.a`) pull-until-fixpoint semantics, and
`.eh_frame_hdr` synthesis, and that is the gap between "our objects" and
"anyone's objects".

## Outside reading, two items, and they are the two that matter

- **John Levine, *Linkers and Loaders*** (Morgan Kaufmann, 1999; the draft
  chapters circulated free for years). Still the standard text. Dated on the
  details, exactly right on the concepts, and short.
- **Ian Lance Taylor's "Linkers" series** — twenty short blog posts by the author
  of `gold`, on `airs.com`. Written for people who want to know why linkers are
  shaped the way they are. Read parts 1-5 and stop; the rest is reference.

The System V x86-64 psABI document is the authority for the relocation table
above, but it is a specification and reads like one — reach for it to check a
detail, never to learn the subject.
