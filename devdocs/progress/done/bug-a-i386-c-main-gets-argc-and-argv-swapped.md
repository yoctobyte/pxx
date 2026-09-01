---
slug: bug-a-i386-c-main-gets-argc-and-argv-swapped
track: A
prio: 80
type: bug
status: done
blocked-by: []
created: 2026-09-01
found-by: frankD
owner: frankC
summary: "FIXED. The i386 C entry stub pushed main's two arguments in the pxx-internal leftmost-first order while a C-defined function on i386 has taken the real SysV cdecl prologue for a while now, so main read argc from the slot holding argv. Swapping the two pushes is the whole change. The stub's comment ASSERTED the internal order and cited the ticket that put it there, so comment and code agreed and were both stale -- settled against gcc rather than against the change log: a pxx --target=i386 --emit-obj object defining int f2(int,int), linked by gcc -m32 into a gcc-compiled main calling f2(1,2), returns 12, so pxx i386 C functions ARE standard cdecl and the stub was the last caller speaking the old convention. Checked the sibling before closing: the hand-emitted longjmp stub reads env at [esp+8] on the OLD premise and is CORRECT, because the C frontend lowers that call through the internal path -- setjmp/longjmp round-trips on i386. Two conventions are live and they are distinguished by which call path reaches the callee, so only this arm moved. Now correct on all five runnable targets including argv[argc]==NULL. Guarded by test/ccross_main_argv.c, wired native plus i386/aarch64/arm32/riscv32; its positive control was RUN (revert the swap, rebuild: `FAIL argc=-6317804 want 3` then SIGSEGV on argv[0]). envp is still not passed to main on ANY target -- unchanged by this and not a regression."
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


## 2026-09-01 (frankC) — fixed. One swap; the interesting part is why it was there

`cparser.inc`'s i386 entry stub pushed `argc` then `argv`. Under cdecl that puts
argv at `[ebp+8]`, which is where main reads its first parameter, so the two
arrived swapped. The fix is the two `EmitB` lines in the other order.

### Comment and code agreed, and both were stale

The stub carried an explicit rationale — the pxx i386 convention pushes
leftmost-first, ir_codegen386's cdecl reversal is disabled inside a C program,
so main reads arg1 from the HIGHER slot — and cited
`bug-c-i386-entry-stub-hands-main-argc-and-argv-swapped`, the ticket that put
the pushes in that order. So this was not a comment contradicting its code; it
was a correct comment that the world moved out from under, which is the harder
case because there is nothing locally inconsistent to notice.

Settled with an oracle that cannot share our mistake rather than by reading the
change log. `pascal26 --target=i386 --emit-obj` on a TU defining
`int f2(int a, int b)`, linked by `gcc -m32` into a gcc-compiled `main` calling
`f2(1,2)`: **12**. pxx's i386 C functions are standard cdecl, and this stub was
the last caller still speaking the old convention.

### The sibling, checked before closing

The old premise has another consumer: the hand-emitted `longjmp` stub reads
`env` at `[esp+8]` and `val` at `[esp+4]`, with a comment saying in as many
words that the pxx i386 ABI is leftmost-deepest. **It is correct and it stays.**
setjmp/longjmp round-trips on i386, because the C frontend lowers that call
through the INTERNAL path, not the cdecl one — `_setjmp` at `[esp+4]` is
one-argument and agrees either way, which is why only the two-argument
`longjmp` ever showed the difference.

So there are genuinely two argument conventions live on i386 in C mode, and
they are told apart by which call path reaches the callee: a C-defined or
external function is `ProcCdecl` and gets real cdecl; a hand-emitted builtin
reached through the internal path gets leftmost-deepest. That is worth knowing
before touching either — the `normalise-dont-special-case` reflex says collapse
them, and the measurement says both arms are exercised and correct today.

### The test, and why no existing one could have caught this

`test/ccross_main_argv.c`, wired native and on all four cross targets. The
existing `ccross_args.c` is the test named after argument passing and it stayed
green throughout, because it exercises calls BETWEEN C functions and never
reads main's own. And the failure hides itself: `argc` came back NEGATIVE, so
`if (argc > 1)` is silently false and the ordinary shape takes the no-arguments
path looking healthy. The new test reads argc as a count, `argv[i]` as a
string, and asserts `argv[argc] == NULL`.

Positive control RUN, not asserted: reverting the swap and rebuilding gives
`FAIL argc=-6317804 want 3` followed by a SIGSEGV dereferencing `argv[0]` — both
failure shapes frankD described, from one test.

### Not done

`envp` is not handed to main on ANY target — x86-64 sets two registers and
stops. Unchanged here, and adding it on i386 alone would be a new asymmetry
rather than a fix.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 67d82d732.
