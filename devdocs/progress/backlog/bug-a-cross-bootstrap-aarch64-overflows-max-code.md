---
track: A
prio: 60
type: bug
blocked-by: []
summary: "`make cross-bootstrap` for aarch64 fails at HEAD with `code overflow: emitted code exceeds MAX_CODE` in compiler/pyparser.inc. Same pinned stable, same source, only the target differs — x86-64 emits 9,343,257 B (56% of the 16 MiB cap) while aarch64 exceeds it, so that backend needs >1.8x the code density for identical input. The error's own suggested remedy does not apply: default and -O2 overflow identically. Unseen because cross-bootstrap runs ONLY on a manual tag dispatch in release.yml, never per-commit, so it can rot at HEAD indefinitely — while the website advertises aarch64 as a supported target."
status: backlog
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

## Scope — two candidate causes, and A picks

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
