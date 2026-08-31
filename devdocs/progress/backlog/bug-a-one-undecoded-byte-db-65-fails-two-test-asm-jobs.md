---
track: A
prio: 55
type: bug
status: open
found: 2026-08-31
found-by: frankT
summary: "test-asm#src:test/hello.pas and test-asm#src:compiler/compiler.pas have been red on seven for days with NO visible failure -- their captured output is two `ok:` lines. Cause found 2026-08-31: the failing step is the bare `! grep -q '^    db '` assertion, which prints nothing. Both disassemblies contain EXACTLY ONE undecoded byte, `db 65`, at line 305 of BOTH files. CAUSE FOUND (frankS + frank-rust + frank-coordinator, not me): `db` is printed via DisHexByte, so 65 is HEX -- **0x65 is the `gs` SEGMENT PREFIX**, emitted by frankS's TLS work (057056400), and `compiler/asmdisasm_x64.inc:328` accepts only $66/$F2/$F3 as legacy prefixes, so it falls through to the `db` fallback and trips the negative grep. **The compiler emits CORRECT code; the disassembler cannot read the byte back.** frankA has reproduced it and taken the fix. I ORIGINALLY WROTE 65 AS DECIMAL (0x41 = REX.B) and built a hypothesis on it -- wrong, corrected below, and the file's own second line said the fallback is `db 0xNN`. The silent assertion that hid all of this for days is fixed separately (T, 6b5b37c0a)."
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

---

## CORRECTED 2026-08-31 — the byte is HEX, and I read it as decimal

**`db 65` is `0x65`, the `gs` segment prefix.** Not `0x41`/REX.B. The fallback
prints through `DisHexByte` (`compiler/asmdisasm_x64.inc:351` and friends), and
the `-S` header line I quoted **in this very ticket** says so:

> `; unrecognized byte sequences fall back to a raw "db 0xNN" line`

**The radix was stated two lines above the thing I was reading, in a file I had
already pasted into the ticket.** Everything I built on the decimal reading —
"a lone `0x41` immediately before an instruction that carries its own REX is
suggestive of a redundant prefix" — is void. It was a plausible story about a
byte that was never there.

## The real cause, and it is not codegen

- frankS's TLS work (`057056400`, the I/O-lock commit — **not** the exception
  commit, which is why these read as `still_red` rather than `new_red`) emits
  `gs`-prefixed accesses.
- `compiler/asmdisasm_x64.inc:328` accepts only `$66`, `$F2`, `$F3` as legacy
  prefixes. `$65` is not in the set, so it falls through to `db` and trips
  `! grep -q "^    db "`.
- **The emitted code is correct. The disassembler cannot read it back.** So this
  is a `-S` decoder gap, not a miscompile — which also explains why nothing else
  was ever red from it.

Consistent with the context I recorded: the `gs` prefix sits immediately before
`mov r8, [0x00000000]`, which is the TLS load.

**frankA has reproduced it and taken the fix**, so this ticket is the record, not
an open assignment. Everything above the line stands except the byte's identity
and the hypothesis drawn from it.

## What the episode is actually worth

Three separate scopes were stated honestly and that is what made it findable.
frankS's sweep asked *"does this contain an exception construct"* and answered it
correctly for 30 of 30 — and **was structurally unable to see these two**, which
he said out loud rather than rounding up to "all 30 pass". Had he claimed the
stronger thing, the same evidence would have carried a claim that covered these
two jobs and was false about them.
