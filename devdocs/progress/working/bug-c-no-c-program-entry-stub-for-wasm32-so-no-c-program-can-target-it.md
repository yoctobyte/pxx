---
slug: bug-c-no-c-program-entry-stub-for-wasm32-so-no-c-program-can-target-it
track: C
prio: 40
type: bug
blocked-by: []
owner: frankA
created: 2026-09-04
found-by: franks-ab (measured while checking whether its crtl signal bridge reached wasm32); filed by frankA
summary: "`--target=wasm32` on ANY C program fails at cparser.inc:11666 with `C program entry stub not implemented for this target yet`, on a trivial `int main(void){return 0;}`. So the whole C x wasm32 cell of the goal's languages-x-platforms product is empty, and every wasm32 measurement anyone has made is a Pascal-only measurement -- including this lane's corpus census, whose source list is Pascal-only for exactly this reason. The same shape was solved once for xtensa (done/bug-cfront-no-entry-stub-for-xtensa), so this is a known pattern with a worked precedent, not new ground."
status: working
---

# No C entry stub for wasm32

Measured 2026-09-04 by franks-ab, checking whether its crtl signal bridge
(`baec9c0bd`) could be reached from C on wasm32. It cannot be reached from C on
wasm32 at all, and neither can anything else.

## Repro

```c
int main(void) { return 0; }
```

```
$ ./compiler/pascal26 --target=wasm32 t.c t.wasm
pascal26:5: error: C program entry stub not implemented for this target yet
```

`cparser.inc:11666`. Independently reproduced by this lane on a larger C
program (a time/exit probe) before the ticket was written -- same message, same
line, and it is the FIRST error, so nothing after it has ever been exercised.

## Why it is worth more than its size

The goal is languages **x** platforms, and this is an empty cell in the product,
not a missing feature in one axis. Everything C-shaped that has been made to
work on wasm32 has been made to work *through Pascal*.

It also silently scopes other people's numbers. This lane's wasm32 gap census
runs over a Pascal-only source list, because a C list would fail before codegen
on every row and land in the census's own "never measured" bucket. So "518
IR_SYSCALL refusals" and every figure derived from it is a claim about the
Pascal frontend on wasm32 and says nothing about the C one. That is not a defect
in the census; it is what the census can physically see.

## The precedent

`devdocs/progress/done/bug-cfront-no-entry-stub-for-xtensa` is the same shape on
the other odd target and was solved. Read that first: whoever takes this should
be checking whether the xtensa stub generalises rather than writing a third one,
because a per-target entry stub written three times is the shape that grows a
fourth.

wasm32 differs from xtensa in one way that matters to the design: a wasm module
has no ELF `_start`, it has a WASI `_start` export, and argv/envp come from
`args_get`/`environ_get` rather than off the stack. The Pascal driver already
does all of that -- `WasmEmitEntry` and the wasi backend's argv/environ path --
so the material exists; the question is whether the C driver can reuse it or
whether the two entry paths need normalising first
(`devdocs/dev/normalise-dont-special-case.md`).

## What would close it

`int main(void){return 0;}` exits 0 under wasmtime, and a C program that calls
`printf` prints. Then re-run the wasm32 gap census over a C source list and
report the denominator, because the current one cannot cover a single C source.
