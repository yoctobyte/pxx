---
track: T
prio: 40
type: feature
status: rejected
found: 2026-09-01
found-by: claude-C
owner: ""
blocked-by: []
summary: "A standing row that compiles a fixed program set with PXXDBG=a.rel8max and alerts when the slack to the +-128 one-byte-jump limit falls below 16. Measured 2026-09-01: the max displacement exercised across self-host plus the whole quick tier is 101, i.e. 27 bytes of headroom, and it is emitted by the --threadsafe lock path -- the region Tracks A and O are actively growing. It is program-INDEPENDENT (54 plain / 101 threadsafe on every Pascal and C source tried), so the number is a property of the runtime/prologue emitters, not of a test corpus. This measures BUDGET only; frankA's cd4af7824 is the sibling class it cannot see."
---

# Track the rel8 displacement budget, so a tight jump is visible before it breaks

Requested by frankA, who proposed a static scan and then withdrew it in favour
of this: *"a static jump/emitter pairing would have been a fragility model I'd
have had to keep true; a max-displacement readout is the fragility itself,
measured."*

## Why a violation scan is not the thing to build

`CheckRel8` (`compiler/rel8.inc`) already hard-errors on a displacement that
does not fit a signed byte, and its coverage is complete — census 2026-09-01:
172 rel8 stores all go through `PatchRel8`/`EmitRel8`, `Patch8` is deleted, and
the 14 remaining raw `Code[..] := Byte(` sites are multi-byte little-endian
patches or ModRM/REX fixups, not displacements. **A violation cannot ship.**

So the missing quantity is the MARGIN. By the time `CheckRel8` fires the slack
is already gone, and it fires for whoever compiles next — possibly a user
rather than the author of the emitter that grew. A slack of 17 bytes and a slack
of 90 are the same clean build.

## The instrument exists

`PXXDBG=a.rel8max` (landed `4def2b06b`) prints, at end of compile, the largest
displacement that compile passed through `CheckRel8` and the slack remaining:

```
$ PXXDBG=a.rel8max ./compiler/pascal26 --threadsafe -Fulib/rtl prog.pas /tmp/p
PXXDBG a.rel8max max=101 (forward jump) slack=27 bytes to the -128..127 limit
```

Measured this way, binary-searching a temporarily lowered bound first and then
confirming with the probe (which reproduced 101 exactly — that agreement is the
probe's positive control):

| build | max | slack |
| --- | --- | --- |
| self-host + entire `gate.sh quick` tier | in [101, 111] | 17–27 |
| any source, `--threadsafe` | 101 | 27 |
| any source, plain | 54 | 74 |

**The max is program-INDEPENDENT.** 54 plain and 101 threadsafe on every Pascal
and C source tried. So the tightest spans live in the runtime/prologue emitters,
not in anything a test program shapes — which is what makes a standing row worth
running at all, and what makes 27 bytes a fact about our shared work area rather
than about a corpus.

## What to build

Compile a small fixed set (one plain, one `--threadsafe`, ideally one per
target that emits rel8) with `PXXDBG=a.rel8max`, parse `slack=`, alert below
**16**. frankA on the floor: *"16 sounds right to me; I have no better number."*

**Assert the compile SUCCEEDED before reading the number.** The report runs at
the end of a successful compile, so a source that fails to compile prints
nothing at all — indistinguishable from a real zero. Measured: plain
`test_mutex.pas` prints silence because it refuses to compile without
`--threadsafe`, and reading that as "no rel8 emitted" is one keystroke away.
Branch on the exit code, do not merely print it.

## The sibling class this does NOT catch — do not let the row imply otherwise

frankA's `cd4af7824` was this same failure with the guard absent, and **a budget
row could not have seen it**: a hand-written literal `jne +8` over a span that
grew when `--emit-obj` wrapped a global store in push/anchor/pop. It never
overflowed rel8. It stayed in range and landed on the `pop` INSIDE the wrapper,
so the nested path popped the caller's return address into `eax` and stored
through it. Clean object, and no relocation count could see it.

So there are two classes and this row addresses one:

- **displacement too large** — `CheckRel8` errors; this row warns first.
- **displacement in range but landing in the wrong place** — needs the
  displacement COMPUTED rather than asserted, which is what `PatchRel8` gives.
  frankA converted that stub. The remaining exposure is any hand-written literal
  jump offset, and finding those is a different job from this one.

## Expected drift, already claimed

frankA has since grown the same region: exported data references are now
symbol-relative in `--emit-obj`, and the i386 address-as-immediate helper adds 6
bytes per site. If `a.rel8max` moves on `--threadsafe` i386 at `742e616ec446` or
later, that is theirs and not drift — ask before bisecting.

## The hand-written-jump population, sized — 2026-09-02 (frankA, recorded by frankC)

The section above leaves "any hand-written literal jump offset" unquantified.
frankA has since sized it, and the instrument matters more than the number.

**`grep` for `EmitB($7x); EmitB(...)` DOES NOT COUNT JUMPS.** It matches ModRM
bytes and the second bytes of two-byte opcodes: `EmitB($0F); EmitB($7E);
EmitB($C0)` is `movq rax, xmm0`; `EmitB($4C); EmitB($89); EmitB($77); EmitB($20)`
is `mov [rdi+32], r14`. Neither is a jump. I quoted "about 25" to frankA off that
grep and frankA had earlier quoted 142 off the same one — **two numbers from one
broken instrument, which is not two sources.** Neither figure appears in this
ticket and neither should be used.

Filtering on the trailing `{ mnemonic }` comment instead gives **36 jcc + 8 `$EB`
sites**, and that instrument can only UNDERCOUNT — it misses any site whose
comment omits the mnemonic. So **~44 is a FLOOR, not a count.**

frankA converted three of them, building the control artefacts with the
pre-change compiler and byte-comparing: every displacement is supposed to be
correct today, so byte-identity is the expected result and a differing byte IS a
bug. **Two of the three differed, both by exactly 8**, and both were shipping on
master (`14bc9d218`): `WriteLn(s:2,'|')` on a ShortString printed `|`, and
`LoadFile` into a ShortString reported `Length(s)=0` for a 21-byte file. The
third was byte-identical, so **the class is not uniform and the control is worth
running per site.**

That ticket went 45 -> 70 and stays with frankA; ~41 sites remain. Nothing here
changes: the budget row still addresses the OTHER class (displacement too large),
and these two were in-range-landing-in-the-wrong-place, which is why no budget
number could have shown them.

## Rejected 2026-09-02 — the Track T tooling backlog was cut as a pile

Owner decision, not a judgement on this ticket individually. 73 of the 74 open
`track: T` tickets were filed between 2026-08-31 and 2026-09-02, 58 on one day.
The pile was too large to work through, and a ticket nobody will fix does not sit
neutrally: it stays in the ranker forever at zero value, which is the same
argument CLAUDE.md already makes for `rejected/` over a low prio.

Four were kept, on a purely structural test — an active umbrella, or a hard
`blocked-by:` edge from live non-T work: `umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**This is a reversible archive, not a deletion.** If one of these is refiled
later, it should be refiled with the evidence that makes it worth doing rather
than restored wholesale.
