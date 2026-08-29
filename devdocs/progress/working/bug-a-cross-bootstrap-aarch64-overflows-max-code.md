---
track: A
prio: 60
type: bug
blocked-by: []
summary: "MEASURED — it is DENSITY, raise the cap. aarch64 codegen runs 2.295x x86-64 across four unrelated programs (spread 2.27-2.34); the compiler needs only 1.80x to breach MAX_CODE, so predicted aarch64 size is 20.4 MB against a 16 MB cap. Runaway ruled out. ~21 MB floor, 32 MB gives headroom, A's call. Originally: `make cross-bootstrap` for aarch64 fails at HEAD with `code overflow: emitted code exceeds MAX_CODE` in compiler/pyparser.inc. Same pinned stable, same source, only the target differs — x86-64 emits 9,343,257 B (56% of the 16 MiB cap) while aarch64 exceeds it, so that backend needs >1.8x the code density for identical input. The error's own suggested remedy does not apply: default and -O2 overflow identically. Unseen because cross-bootstrap runs ONLY on a manual tag dispatch in release.yml, never per-commit, so it can rot at HEAD indefinitely — while the website advertises aarch64 as a supported target."
status: working
owner: frankA
---

# `cross-bootstrap` for aarch64 overflows `MAX_CODE`

Measured 2026-08-27 by the `ianweb` session on `via`; the constants and the CI
configuration verified independently in `/home/neo/frank2` at `7ff0bc1cc`.

**Filed here rather than by the finder deliberately.** `ianweb`'s operator
cleared push for the **website** repo in the context of website work, and it
declined to read that as clearance for the compiler repo — correctly. See
[[decide-deploy-key-on-via]] for why the scope boundary on that credential is
the load-bearing part.

## The measurement

Same pinned stable, same source, only the target differs:

| target | result |
| --- | --- |
| `--target=aarch64` | **OVERFLOW** — `code overflow: emitted code exceeds MAX_CODE`, at `pascal26:48080`, in `compiler/pyparser.inc` |
| native x86-64 (control) | **OK** — code 9,343,257 B · data 253,784 B · procs 3316 |

`MAX_CODE = 16777216` (`compiler/defs.inc:10`) = 16 MiB. **x86-64 uses 55.7% of
the cap.** aarch64 exceeds it on identical input, so that backend needs **more
than 1.8x** the code size.

**The control is what makes this a codegen-density finding rather than a growth
finding.** "The source outgrew the cap" would fail on both targets. It does not.

## The error's own remedy does not apply — say so, to save the next reader

`compiler/emit.inc:20` advises:

> Raise it if this is growth rather than runaway emission; note that **LOWER -O
> levels emit MORE code**, so a build that fits at -O2 can still overflow at -O0.

`ianweb` ran both. **Default and `-O2` overflow identically** — same site, same
file. So the documented escape is exhausted before this ticket starts.

## The half that matters more: this gate is not in the loop

`.github/workflows/ci.yml:10` — verified — records that per-commit CI is
**deliberately light**: no FPC, no QEMU, no cross-targets. It seeds from the
committed native stable, self-hosts to a fixedpoint, runs a hello. **`make
cross-bootstrap` lives in `release.yml` on a manual tag dispatch only.**

So the check that would prove the aarch64 claim is not in the loop that would
catch it breaking, and this can rot at HEAD indefinitely — which it evidently
has. Meanwhile pxxc.org advertises ARM among the supported targets. That is the
same doc-vs-reality shape as
[[docs-web-nilpy-is-still-billed-as-experimental]], pointing the other way: there
the site understated what works, here it may overstate it.

**Do NOT widen this ticket into "make cross-bootstrap per-commit".** That is a
real and larger question — it needs FPC and qemu in CI and it costs minutes per
push — and it would swallow this. File it separately if it is wanted.

## MEASURED 2026-08-27 — it is DENSITY, not runaway. Raise the cap.

`ianweb` ran the per-proc comparison this ticket asked for. Four unrelated
programs, same shim, same stable, `code=` bytes x86-64 → aarch64:

| program | x86-64 | aarch64 | ratio |
| --- | --- | --- | --- |
| `hello.pas` | 64,110 | 150,064 | 2.34x |
| `test_inline_expand.pas` | 116,756 | 264,708 | 2.27x |
| `test_variant_class_cross.pas` | 111,770 | 256,980 | 2.30x |
| `test_collections.pas` | 115,775 | 262,300 | 2.27x |

Spread **2.27–2.34, mean 2.295x** — flat across a hello-world, an inliner
stress, a variant/class cross case and a collections program, which have nothing
in common but the backend. **Concentration would have shown as one program well
off 2.3x. None is.**

Against the compiler:

```
x86-64 compiler code        9,343,257 B
MAX_CODE                   16,777,216 B
ratio needed to overflow         1.796x
observed baseline density        2.295x
predicted aarch64 size     21,442,775 B   (20.4 MB)
overflows by                4,665,559 B   (4.4 MB)
```

**The compiler needs only 1.80x to breach the cap and the backend's ordinary
density is already 2.29x.** So the overflow is exactly what uniform density
predicts — it would happen for *any* program of that size, and `pyparser.inc` is
merely where the running total crossed the line. **The site of a cap breach is
an accident of ordering, not a location**, which is why it reported somewhere
uninteresting.

**So cause 1 (growth/density) is confirmed and cause 2 (runaway) is ruled out on
four samples.** The "don't raise a cap on a runaway" warning does not bite here.
~21 MB is the floor; **32 MB gives real headroom**. Still A's call — a smaller
bump may be preferred for reasons not visible from the measurement.

**Caveat, stated so the numbers are not over-read:** these are the *pinned*
stable's aarch64 codegen, not HEAD's. If that backend has improved since the
pin, the real ratio is lower and 20.4 MB is an overestimate — but not by enough
to fit, since even 1.80x breaches the cap and the observed floor is 2.27x.
Someone on x86-64 can settle it exactly by building the compiler at HEAD for
aarch64 with a raised cap and reading the actual `code=`.

**Worth asking while in `defs.inc`:** this is the *second* fixed cap in that file
to bite, and it bit next to the comment recording the first
([[bug-a-string-table-cap-refuses-a-14k-line-c-program]], `defs.inc:25`). Does
any remaining fixed cap there have a headroom check, or do we wait for the third?

## SUPERSEDED — two candidate causes, and A picks

1. **Growth**: 16 MiB is simply too small for aarch64's density and `MAX_CODE`
   should rise. Cheap, and there is precedent —
   [[bug-a-string-table-cap-refuses-a-14k-line-c-program]] was the same family
   of fixed-cap problem.
2. **Runaway emission** in the aarch64 backend, with `pyparser.inc` merely being
   the file large enough to hit the wall first.

**Prefer measuring before choosing.** A 1.8x ratio is large but not obviously
pathological for a fixed-width ISA against x86-64's variable-length encoding;
what would settle it is a per-proc size comparison across the two backends, to
see whether the excess is uniform (density, so raise the cap) or concentrated
(runaway, so fix the emitter). Raising the cap on a runaway just moves the wall.

## Provenance note

FPC 3.2.2 is installed on `via` (for compliance testing) and was **not involved**:
the bootstrap attempt used the pinned pxx stable to compile pxx source start to
finish. Recorded because "was this FPC-contaminated?" is the first question a
reader of a bootstrap failure asks.

---

## RESOLVED 2026-08-29 (frankA) — cap raised to 32 MB, and arm32 was broken too

`ianweb`'s analysis was right and its prediction was close. The one thing it
could not do from `via` — build the compiler for these targets at HEAD and read
the real number — is done here, and it changed two things.

### Measured at HEAD, not predicted

`compiler.pas -dPXX_MANAGED_STRING` (the `CROSS_BOOTSTRAP_FLAGS`), one compiler,
one source, only `--target` differing:

| target | code | % of the OLD 16 MB cap |
| --- | --- | --- |
| x86-64 | 9,316,078 B | 55.5% |
| i386 | 10,902,436 B | 65.0% |
| **aarch64** | **20,446,704 B** | **121.9% — overflowed** |
| **arm32** | **21,568,956 B** | **128.6% — overflowed** |

Predicted 21,442,775 B for aarch64; actual 20,446,704 B — **4.6% high, in the
direction the ticket's own caveat named** (the estimate used the pinned stable's
backend, and HEAD's is slightly better). The real ratio is **2.19x**, not 2.295x.
The conclusion is unchanged: 1.80x breaches the cap and the floor is still well
above it.

### ARM32 WAS ALSO BROKEN, and nobody had said so

**`arm32` is 1.1 MB worse than aarch64** and `make cross-bootstrap` builds
`aarch64`, `arm32` and `i386`. So the ticket's title names one of two broken
targets. It went unreported for the same reason the first one did: nothing runs
it. Had the cap been raised to the ticket's ~21 MB floor rather than to 32 MB,
**aarch64 would have fitted and arm32 would still have overflowed** — the fix
would have looked complete and been half.

That is the concrete argument for measuring every target rather than the one in
the ticket, and it is why the headroom number below is quoted against arm32.

### The decision — A's call, per the ticket

**32 MB.** At that cap the densest target (arm32) sits at **64.3%**, which is
approximately where x86-64 sat under the old cap — so the headroom is now sized
for the target that needs it rather than the one that does not. The ~21 MB floor
is rejected for the reason above: it clears the reported target only.

### The cost is nothing, and the old note was wrong about it

`defs.inc` said the cap *"costs virtual BSS only: Code[] plus AsmDisProcAtPos"*.
That was true when both were fixed arrays. **Both are `array of` now** —
`GrowCode` doubles `Code[]` on demand and stops at `MAX_CODE`, and
`AsmDisProcAtPos` is `SetLength`'d to the actual `CodeLen`. The constant is a
ceiling, not an allocation. Measured across the bump: BSS `76206356` ->
`76249388`, i.e. it moved with the rebuild and not with the cap. The comment is
corrected in place.

### Not folded in, deliberately

- **Making `cross-bootstrap` per-commit.** The ticket says not to and it is
  right: it needs FPC and qemu in CI and costs minutes per push. The exposure is
  real — nothing was red because nothing asked, while the site advertises ARM —
  but it is a separate ticket.
- **riscv32** fails this build for an unrelated reason
  (`standard builtin calls not supported in bare-metal stage 1`), is not part of
  `cross-bootstrap`, and is not touched here.
- **The closing question — "do we wait for the third?"** — is answered: **this
  ticket WAS the third** (`MAX_CODE` 8->16, `MAX_STRS` 8192->65536, `MAX_CODE`
  16->32), and all three were found by a program failing rather than by anyone
  looking, because no cap's utilisation is reported anywhere. Filed as
  [[feature-a-report-fixed-cap-headroom]] (A, p40) rather than built here.
