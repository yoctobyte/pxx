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
