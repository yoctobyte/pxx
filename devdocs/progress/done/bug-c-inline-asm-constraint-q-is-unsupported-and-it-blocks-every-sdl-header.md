---
slug: bug-c-inline-asm-constraint-q-is-unsupported-and-it-blocks-every-sdl-header
track: C
prio: 55
type: bug
status: done
owner: "frankH"
created: 2026-09-08
found-by: frankuser
tags: [cfront, inline-asm, sdl2, headers, lekkerzeilen]
blocked-by: [bug-a-the-x86-64-encoder-cannot-name-a-high-byte-register]
summary: "DONE for the constraint, AND THE TITLE'S SECOND CLAUSE WAS WRONG. `Q` and `q` are supported now -- a restricted register class (a/b/c/d), allocated before the general pool, both letters honoured as the same four because SDL_endian.h declares SDL_Swap16 twice, \"=q\" under __i386__ and \"=Q\" under __x86_64__, so one letter compiles that header for one target and refuses it for the other. Also implemented the `%b` and `%w` operand modifiers, whose absence was the NEXT wall on the same line and which a comment in asmatt.inc claimed were already read. SDL2 STILL DOES NOT IMPORT, and the constraint was never the only reason: `%h0` needs a HIGH-byte register, which the x86-64 encoder cannot name at all -- filed as bug-a-the-x86-64-encoder-cannot-name-a-high-byte-register. A second wall in front of it arrived independently: `import \"/usr/include/SDL2/SDL.h\"` now stops at the derived-soname guard (`libsdl.so`) before it reaches any asm. Measured: libSDL2-2.0.so.0 exports SDL_Init and SDL_CreateWindow, so a dynsym-verified directory heuristic would resolve it."
---

# Repro

```
$ printf 'import "/usr/include/SDL2/SDL.h"\nprint("reached")\n' > h.py
$ ./compiler/pascal26 h.py out
pascal26:167: error: C: inline asm constraint "=Q" is not supported
```

`SDL_endian.h:166`: `__asm__("xchgb %b0,%h0": "=Q"(x):"0"(x));` — SDL's
16-bit byteswap.

# What `Q` means, and why the machinery is probably already there

In GCC's x86 constraint set, `Q` is *any register addressable as `rl`/`rh`* —
i.e. one of `a`, `b`, `c`, `d`. The diagnostic's own list says this frontend
already reads **the fixed-register letters a b c d**. So `Q` is the
"any one of the four" form of letters that already exist, rather than a new
register class.

**That is an argument for where to look, not a claim that the fix is one line.**
The difference between a fixed letter and a choose-one-of-four letter is
allocation, and this ticket has not read that code.

# Scope beyond SDL

`Q` is common in hand-written x86 headers wherever a byte-half register is
needed. Whoever fixes it should check the sibling letters in the same family
(`R`, `q`, `l`) rather than adding one row — the neighbours are the same
mechanism and the second path is the one that stays broken.

Same family as the resolved
`bug-c-inline-asm-is-x86-64-only-so-five-busybox-tus-refuse-on-i386`.


## Resolved 2026-09-10, frankH — and the ticket was right about the letter and wrong about the consequence

### What landed

`Q` and `q` in `cparser.inc` as a RESTRICTED register class, which is the thing
the ticket correctly said it was: *"the difference between a fixed letter and a
choose-one-of-four letter is allocation, and this ticket has not read that
code."* That sentence was the accurate part. `CAsmFixedReg` could not carry it —
it answers with one register — so there is a third allocation phase between the
fixed pins and the general pool, taking c/a/d before the callee-saved b.

Both letters are honoured as the same four. On x86-64 `q` legally permits all
sixteen and is narrowed here, for the same reason `g` is honoured as `r`: a
subset of what a constraint permits is a choice it allows. One mechanism
instead of two that differ per target.

Then `%b` and `%w`, which were the NEXT wall on the same source line. A comment
in `asmatt.inc` read *"%N, or a modifier like %b0 / %w0 / %k0 / %l0"* and the
code read only a bare digit — the comment was the aspiration, the code was the
truth. Decided by measuring rather than reconciling: across every header on this
box the modifiers that occur are `%w1` (12), `%b0` (6), `%w0` (5), `%h0` (4),
and no `%k`, `%l`, `%q` or `%z`. `R` and `l` constraint letters do not occur
either, so they stay refused by name.

### The title's second clause is the part to correct

*"…and it blocks every SDL header"* — it did, and it was not alone, which the
ticket had no way to see because the compiler stops at the first error. Two more
walls stand between here and an SDL2 import, and neither is this one:

1. **`%h0`** — the high byte. The encoder cannot name `ah/ch/dh/bh` at all: at
   byte width it FORCES a REX prefix for register numbers 4..7, and REX is
   precisely what makes the high-byte forms unencodable. Emitting one anyway
   assembles quietly to `spl`. Refused by name and filed as
   [[bug-a-the-x86-64-encoder-cannot-name-a-high-byte-register]].
2. **the derived soname** — `import "/usr/include/SDL2/SDL.h"` now stops before
   any asm, at `memcmp` being imported from `libsdl.so`, a name the compiler
   invented from the header's stem. That guard is correct and is not this
   ticket's.

So `=Q` was a queue position, not a size — which is what
`umbrella-pxx-compiles-fpc-itself` measured four times today and what CLAUDE.md
now says about first-failure censuses generally.

### A measurement for the soname wall, since it is now the front of the queue

`feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym`
was declined on a counterexample: `net/if.h` would derive `libnet.so.9`, which
is a real installed library, so a presence check passes and the build dies on
`undefined symbol` — a quiet failure traded for a loud one. That reasoning is
right about a PRESENCE check and the ticket's own title names the discriminator
the objection does not reach. Measured on this box:

| header | derived | exports the header's symbols? |
| --- | --- | --- |
| `SDL2/SDL.h` | `libSDL2-2.0.so.0` | **yes** — `SDL_Init`, `SDL_CreateWindow` |
| `net/if.h` | `libnet.so.9` | **no** — zero of them; `if_nametoindex` is in libc |

A dynsym check accepts the first and rejects the second. That is not a
recommendation to land it — whoever does owns the population question this
table does not answer — but the declining counterexample does not survive the
verification step the ticket is named for.

Test: `test/casm_byte_classes.c`, four rows against gcc on identical source.
`b_wrap` is the row that separates a byte add from a 32-bit one (0x12FF + 1 is
0x1200, where a 32-bit add carries into the second byte). The pre-fix compiler
refuses the file by name, verified by revert and rebuild.
