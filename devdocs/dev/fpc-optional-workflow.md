# FPC-optional workflow — the daily loop needs no Free Pascal

PXX is self-hosting. The pinned native binary in `stable_linux_amd64/` is a
known-good seed, committed to git. So **day-to-day compiler work — build, test,
stabilize, pin — does not need FPC installed.** You can `apt remove fpc` and keep
developing.

FPC is kept for exactly two reasons, both demoted to last-resort / postcheck:

1. **Cold start from pure source** — a checkout with *no* committed binary at all
   (e.g. a distro packaging the source tarball). Something has to compile gen0.
2. **FPC-compliance regression guard** — proof that FPC can *still* compile us and
   yields the same self-hosted binary. Valuable, but not a precondition for a pin.

## Three seeds, FPC is the heaviest

To rebuild the compiler you need *a* working compiler to compile it with. Three
valid seeds, in order of preference:

| Seed | Command | FPC? | Use when |
|------|---------|------|----------|
| existing `compiler/pascal26` | `make compiler/pascal26` / `make test` | no | you edited the compiler and a working binary is already present |
| committed pinned stable binary | `make seed-from-stable` then `make test` | no | fresh checkout, no working binary yet |
| FPC | `make bootstrap` | **yes** | pure source, no committed binary anywhere |

`make selfcheck` seeds from the committed stable and proves a self-host fixedpoint
(`g2 == g3`) plus a compiled `hello` — the fast, FPC-free sanity loop CI uses.

### How stale a seed may be — measured, ~1 week

A pinned binary is **not** an indefinitely valid seed. Measured 2026-08-07
against current source, each pin extracted with its own frozen `builtin/`:

| pin | date | age | result |
|-----|------|-----|--------|
| v246 | 08-07 | 0d | OK |
| v242 | 08-04 | 3d | OK |
| **v238** | **08-01** | **6d** | **OK** — product runs, C == D fixedpoint, byte-identical to the shipped HEAD binary |
| v233 | 07-31 | 7d | **FAIL** — `case label must be constant` |
| v228 | 07-28 | 10d | **FAIL** — same |

The cause is precise, and it is a property of self-hosting rather than a bug:

- **2026-08-01**, `e4995a457` *"fold Ord/Chr/Length/Succ/Pred in constant
  expressions and case labels"* gave the compiler that capability;
- **2026-08-03**, `abd709361` had the compiler's OWN source start using it —
  `case ASTIVal[n] of Ord(tkEq), Ord(tkNeq), …` in `pyparser.inc`.

From that moment every seed older than 08-01 was cut off, because it cannot
parse the source it is being asked to compile.

> **The seed window is set by the newest compiler feature the compiler's own
> source depends on.** It shortens the moment the source adopts something fresh,
> not gradually.

Two consequences worth holding on to:

1. **Keep the committed pin reasonably fresh.** It is the cold-start seed for
   anyone without FPC, and it silently stops working about a week after the
   source adopts a new feature.
2. **This is the real justification for keeping FPC** (reason 1 at the top of
   this page). It is not a fallback for "big changes" — layout changes self-host
   fine from seed 2. It is the escape hatch for a checkout whose committed binary
   has aged past the window, and for pure source with no binary at all.

**The obvious lever is deliberately rejected.** One could widen the window by
having the compiler's own source lag its own features by a release or two —
avoid `Ord()` in a case label until every seed in circulation can fold it. Do
not propose this: it is **compiler-appeasement in the compiler's own source**,
which CLAUDE.md's *"Platonic code — no compiler-appeasement workarounds (all
tracks)"* forbids, and that section names self-hosting explicitly rather than
exempting it.

The narrow window is therefore a **consequence of policy, not a defect**. The
compiler's source uses the language as it should be written, the moment the
compiler supports it; the seed window pays for that, and FPC is what covers the
gap. Recorded so this is not "improved" later by someone who has not connected
the two.

### The one case where seed 1 is the wrong seed

`compiler/pascal26` is the fast path and is the right default: the RTL rarely
changes in ways that matter, and when it doesn't, seed 1 is strictly the
quickest. But it is the only seed with **no versioned RTL**. It resolves `uses
builtinheap` from the LIVE tree, whereas the pinned binary resolves it from the
frozen `stable_linux_amd64/default/builtin/` beside it (`make pin` puts it
there). So:

> If you change a **data layout that both the emitted code and the RTL must
> agree on** — the managed-block header being the example — seed 1 links
> tomorrow's RTL into today's emitter. **Use seed 2.**

This fails in an unusually expensive way: the compile **succeeds**, and the
binary it produces dumps core. `make compiler/pascal26` iterates to convergence,
so the crash lands in round 2 and reads as a codegen bug in whatever you just
touched.

Measured 2026-08-07 with the 16→24 byte header change
(`feature-a-managed-block-kind-word`): seed 1 produced a core-dumping compiler;
seed 2 produced a working one that reached a fixedpoint **byte-identical** to an
FPC-seeded build. **Seed 3 (FPC) is not required for this** — that was the
session's wrong conclusion, from a control run in the wrong directory. See
`devdocs/dev/managed-block-header.md` and
`bug-a-self-host-seed-has-no-versioned-rtl`.

**Since 2026-08-07 you get told instead of finding out.** `PXX_RTL_LAYOUT_VERSION`
is declared twice — in `compiler/defs.inc` (the layout this compiler's inline
codegen EMITS) and in `compiler/builtin/builtinheap.pas` (the layout the RTL
IMPLEMENTS) — and the compiler compares them when it links that unit. A stale
seed now refuses with a message naming the cause and the remedy rather than
building a compiler that compiles clean and crashes later.

So when you change such a layout: **bump BOTH constants together.** Your current
`./compiler/pascal26` then refuses (it has the old number compiled in), which is
the signal to use seed 2. After one reseed the numbers match and the fast path
is back. A frozen builtin that predates the stamp has no constant at all, and
absence is treated as unknown-and-allowed, so older pins keep working.

## The gate, decoupled

```
make test       # DAILY gate — FPC-free: test-core + test-debug-g + lib-fpc-clean
                #   self-hosts off the existing compiler/pascal26 (no FPC).
make test-fpc   # POSTCHECK — the FPC-dependent checks, NOT in the daily gate:
                #   fpc-check  (FPC compiles us, byte-identical to self-host)
                #   test-asm-emit (host-built byte oracle for the assemblers)
make stabilize  # = make test + 4-iteration fixedpoint, then records stable_latest.
                #   No longer pulls FPC transitively — you can pin without fpc.
make pin        # bless stable_latest -> pinned (hands Track B a new compiler).
```

Before this split, `test: fpc-check …` and `stabilize: test`, so **every pin
required FPC**. Now FPC only runs when you ask for it (`make test-fpc`, `make
bootstrap`).

## Where FPC still runs (on purpose)

- `tools/release.sh` `run_gate()` runs `make test` **and** `make test-fpc` (plus
  `make cross-bootstrap`) — the release build keeps full FPC-compliance.
- `.github/workflows/ci.yml` runs `make selfcheck` (no FPC); only on its failure
  does the `bootstrap-fallback` job install FPC and `make bootstrap`. So normal CI
  is already FPC-free; FPC is the safety net.

## Cold-start cheat sheet

```sh
# Have the repo (committed stable binary present) — no FPC needed:
make seed-from-stable && make test

# Pure source, nothing prebuilt — the only FPC path:
sudo apt install fpc
make bootstrap && make test
make test-fpc          # optional compliance proof
```
