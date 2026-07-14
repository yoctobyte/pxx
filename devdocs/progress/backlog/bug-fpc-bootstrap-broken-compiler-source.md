---
summary: "compiler.pas no longer builds under FPC — the bootstrap seed is broken; the source has drifted onto pxx-only laxity"
type: bug
prio: 76
---

# `make bootstrap` is broken: FPC can no longer compile `compiler/compiler.pas`

- **Type:** bug (bootstrap chain). **Track A** (compiler core / self-host).
- **Status:** backlog
- **Opened:** 2026-07-14
- **Found by:** Track T. The `fpc` level of the bench suite reported
  `selfcompile FPC-COMPILE-FAIL`, which is the same failure tstate has been carrying as
  an open regression: **`fpc-bootstrap#src:compiler/compiler.pas`, `bad=603cf2bda859`**.
  It had no ticket — only a tstate row — so it was being carried indefinitely without an
  owner. **T owns the tool, never the bug**: filed here, not fixed there.

## Why this matters more than a red row

**FPC is the SEED.** The whole self-hosting story is "FPC-seeded": you build `pascal26`
with FPC once, and from there the compiler compiles itself. If FPC cannot compile
`compiler.pas`, then **a from-scratch build is impossible** — the only way to get a
working compiler is the committed `stable_linux_amd64/**` binary. The bootstrap chain
that makes the self-host claim meaningful is, right now, cut. Nobody noticed day to day
because every track builds from the pinned binary.

It also silently costs us an oracle: `selfcompile`'s `fpc` level (the historic
"how fast is pxx vs FPC compiling the same source" number) cannot be recorded at all
while this is red.

## Repro

```
fpc -Mobjfpc -O2 -Tlinux -Px86_64 -FU/tmp/u -FE/tmp/u -o/tmp/p26 compiler/compiler.pas
```

At HEAD (`db01a921`), five errors:

```
parser.inc(7875,9)          Error: Identifier not found "EnableExceptionRuntime"
ir.inc(798,8)               Error: Identifier not found "IsASTLValue"
ir_codegen_riscv32.inc(276) Error: Identifier not found "IREmitNodeRISCV32"
ir_codegen_riscv32.inc(285) Error: Identifier not found "IREmitNodeRISCV32"
cparser.inc(9043,55)        Error: Incompatible type for arg no. 1:
                                   Got "TTypeKind", expected "LongInt"
compiler.pas(921)           Fatal: There were 5 errors compiling module, stopping
```

(The same five appear with and without `-Mobjfpc`, so this is not a dialect-flag issue.)

## The actual cause: our source now leans on pxx's own laxity

This is the part worth internalising, because it will keep happening. **pxx is more
permissive than FPC**, and `compiler.pas` — being compiled almost exclusively *by pxx*
these days — has quietly drifted into that permissiveness. Two distinct classes:

1. **Use before declaration** (4 of the 5). `EnableExceptionRuntime`, `IsASTLValue` and
   `IREmitNodeRISCV32` are called before they are declared. pxx resolves them anyway;
   FPC, correctly for Pascal, requires a declaration first. `IREmitNodeRISCV32` is
   mutually recursive and needs a genuine **`forward;`** declaration — the other two look
   like ordering-within-an-include problems.
2. **Implicit enum → integer** (1 of the 5). `cparser.inc:9043` passes a `TTypeKind`
   where a `LongInt` parameter is expected. pxx accepts it; FPC wants an explicit
   `Ord()`/cast.

Both are things *the compiler itself is lax about*. The self-host gate cannot catch them
by construction: pxx compiling pxx will always accept pxx's own laxity. **Only FPC can
see this class of drift**, which is exactly why the FPC bootstrap needs to stay green
rather than being allowed to rot.

Class 2 is arguably also a **dialect question for Track P** — should pxx accept an
implicit enum→integer argument at all? FPC does not, and `--strict-*` flags exist for
precisely this kind of parity. But the *fix here* is to make the source compile under
both, not to relitigate the dialect.

## Note on the bisect

tstate blames `603cf2bda859` ("fix(c): anonymous bit-fields"), which plausibly introduced
the `cparser.inc` `TTypeKind` error — but the four use-before-declaration errors are in
`parser.inc` / `ir.inc` / `ir_codegen_riscv32.inc`, files that commit never touched. So
they are almost certainly **older drift** that the job simply did not observe until it
started running. Do not assume reverting the blamed commit fixes this; fix the five.

## Acceptance

- `fpc -Mobjfpc -O2 -Tlinux -Px86_64 compiler/compiler.pas` builds clean.
- `make bootstrap` works from a checkout with no `stable_linux_amd64/**` binary present —
  i.e. the from-scratch path actually works, not just the incremental one.
- The FPC-built compiler reaches self-host fixedpoint (byte-identical), which is the
  proof the seed is genuinely usable and not merely compiling.
- The `fpc-bootstrap` tstate job goes green, and `selfcompile`'s `fpc` bench row starts
  recording again.
- **Keep it green:** the FPC bootstrap must stay a gate somewhere (tstate job is enough),
  because pxx-compiling-pxx structurally cannot detect this drift.
