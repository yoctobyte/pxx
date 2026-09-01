---
slug: bug-a-i386-c-main-gets-argc-and-argv-swapped
track: A
prio: 80
type: bug
status: new
blocked-by: []
created: 2026-09-01
found-by: frankD
owner: ""
summary: "On --target=i386 a C main() receives argc and argv SWAPPED: argv holds the integer argc and argc holds a garbled pointer. Every argument-reading C program on i386 is wrong, and one that indexes argv[1] segfaults. Pascal's ParamCount/ParamStr on the same target are CORRECT, so this is the C entry bridge, not the process entry. x86-64, aarch64, arm32 and riscv32 are all fine."
---

# i386: a C `main` gets argc and argv swapped

Compiler binary sha256 `0e1ed8c673bc`, at commit `d86bb32fe`. Found while
testing crtl `chown`/`lchown` across every runnable target for
[[feature-c-corpus-busybox-multi-applet]] — the i386 run segfaulted where the
other five passed, and the cause was not chown.

## The measurement

```c
int main(int argc, char **argv) { printf("argc=%d argv=%p\n", argc, (void*)argv); }
```

```
$ pascal26 --target=i386 ap2.c ap2 && tools/run_target.sh i386 ap2 one two
argc=-3852524 argv=0x3
```

`argv` is `0x3` — which is the real `argc` (program + two arguments). `argc`
holds a pointer's low bits. They are swapped.

`argc > 0` is therefore usually FALSE (the pointer reads as negative), so the
common shape silently takes the no-arguments path; a program that reaches
`argv[1]` regardless dereferences `3` and segfaults.

## What it is NOT

**Not the process entry.** Pascal on the same target is correct:

```
$ pascal26 --target=i386 argvprobe.pas app && tools/run_target.sh i386 app one two
2
one
```

`ParamCount` and `ParamStr` both answer correctly, so the kernel's initial
stack is being read properly and the fault is in what hands `main` its two
arguments on i386 specifically.

**Not a regression from a working state.** `stable_linux_amd64/default/pinned`
cannot build C for i386 at all (`target i386: call argument count mismatch
(defaults not supported yet)` in `lib/crtl/src/fcntl.c`), so this surface is
new work rather than something that used to pass.

**Not shared with the other targets.** x86-64, aarch64, arm32 and riscv32 all
print `argc=3 argv0=<path>`.

## Acceptance

- `argc`/`argv` correct on i386 for a C `main`, including `argv[argc] == NULL`
  and `envp` if the third parameter is supported.
- A row in whatever test covers process arguments, run on i386 — the defect is
  invisible to any test that does not read them, which is why it survived.

## Coordination

**Not frankA** — he confirmed on 2026-09-01 that his day was `ir_codegen.inc`,
`rtti_emit.inc`, `builtinheap.pas` and `symtab.inc`, with no i386 or object
work. An earlier version of this section named him, wrongly: I read the **lane
tags** on the i386 commits (`feat(A)`, `feat(A,C)`) as agent names.

What is true is about the CODE, measured: the i386 C path moved several times
this week — `b392fd5d0` (i386 object links as a hardened PIE), `f39e158dd` (the
SysV argument PLACEMENT oracle, checked against gcc's register choices),
`747d3479f` (struct-by-value across a real gcc link). Argument placement is
exactly this defect's neighbourhood, so ask who is in it before starting rather
than inferring an owner from a commit tag.
