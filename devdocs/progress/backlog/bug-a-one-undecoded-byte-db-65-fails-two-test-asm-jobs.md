---
track: A
prio: 55
type: bug
status: open
found: 2026-08-31
found-by: frankT
summary: "test-asm#src:test/hello.pas and test-asm#src:compiler/compiler.pas have been red on seven for days with NO visible failure -- their captured output is two `ok:` lines. Cause found 2026-08-31: the failing step is the bare `! grep -q '^    db '` assertion, which prints nothing. Both disassemblies contain EXACTLY ONE undecoded byte, `db 65` (0x41 = REX.B), at line 305 of BOTH files, in an identical region -- so it is in the shared runtime preamble, not in program code. It sits between `mov rax, 0x0f; syscall` and `mov r8, [0x00000000]`. NOT DIAGNOSED FURTHER, deliberately: whether codegen emits a stray prefix or the `-S` decoder loses sync there is Track A's call, and T owns the tool, not the bug. The silent assertion is fixed separately (T); this ticket is the byte."
---

# One undecoded byte fails both `test-asm` disassembly jobs

## What is measured

Compiler `4ab02d96a777` (self-host fixedpoint verified at HEAD, *"converged
after 2 round(s)"*; `pinned` is `992065f21f33`, different, so this is not the
pinned binary).

```
./compiler/pascal26 -S test/hello.pas        <out>   ->  exit 0
./compiler/pascal26 -S compiler/compiler.pas <out>   ->  exit 0
grep -c '^    db ' <either>.s                        ->  1
grep -n  '^    db ' <either>.s                       ->  305:    db 65
```

**Identical line number in both, and the surrounding region diffs clean**, so
this is one site in the shared preamble rather than anything program-specific.
Context:

```
    mov rax, 0x0000000f
    syscall
    db 65                 <- 65 decimal = 0x41 = REX.B
    mov r8, [0x00000000]
    add r8, 32
```

The `-S` header says it itself: *"unrecognized byte sequences fall back to a raw
`db 0xNN` line."* So the assertion `! grep -q "^    db "` is asserting that every
byte decodes, and exactly one does not.

## Why it was invisible for days

The failing step was a bare `! grep -q`, which prints **nothing**. The jobs'
captured output in `seven.json` is:

```
ok: $TMP  [-S disassembly] | ok: $TMP  [code=65304B  data=2760B  bss=42468B  procs=130]
```

Two successes and no failure. Three agents looked at that report in one night
(frankA and frankS both flagged the pair as unowned; I was the third) and none of
us could say what had failed. **Fixed on the T side in the same push** — the five
assertions in the `test-asm` block now name what they looked for and print the
offending line. The assertions themselves are unchanged.

## What I did NOT determine, and why it is yours

Whether this is **codegen emitting a stray `0x41`** or the **`-S` decoder losing
sync** at that point. Those have different fixes and only one of them is a real
defect in emitted code. I tried to cross-check with a second decoder and could
not: `objdump -d` on our ELF produced only the file header and no disassembly at
all, so it is not usable as an oracle here without further work.

A lone `0x41` immediately before an instruction that carries its own REX
(`mov r8, …` needs REX.B) is at least suggestive of a redundant prefix rather
than random data — but that is a hypothesis I did not test, and `root-cause-over-
microfix.md` applies: vary the shape before believing it.

## Cheapest next step

`PXXDBG=a.ir:<proc>` / the emitter around the `rt_sigreturn` sequence, or simply
find which emitter writes the bytes at that offset. It reproduces in one command
on any program, including `test/hello.pas`, so the repro cost is a compile.
