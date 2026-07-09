---
prio: 60
---

# C corpus: chess engine — perft as a compiler-independent oracle

- **Type:** feature (C frontend validation) — Track A/C.
- **Status:** backlog — planned 2026-07-09, after c-testsuite hit 220/220 + zlib/tcc green.
- **Parent:** [[feature-c-corpus-expansion]] (this is the next rung after tcc).

## Why chess / why perft
A chess engine is **pure math + bit tests + deep recursion + near-zero I/O** — a
different muscle than lua/sqlite/tcc (parsers, VMs, string churn). The killer feature
is the oracle: **perft** (move-path enumeration to depth N) has **canonical
known-answer values that are compiler-independent** — no gcc oracle build needed, the
numbers ARE truth. It also **cross-validates the Rust frontend**: `test_rust_chess_perft.rs`
already computes perft (20/400/8902) through the Rust path; a C engine hitting the same
numbers triangulates C and Rust against one ground truth.

### Canonical perft values (chessprogramming.org — DO NOT re-derive)
- **startpos**            perft(1..6) = 20, 400, 8902, 197281, 4865609, 119060324
- **Kiwipete** `r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -`
                          perft(1..5) = 48, 2039, 97862, 4085603, 193690690
- **Position 3** `8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - -`
                          perft(1..6) = 14, 191, 2812, 43238, 674624, 11030083
- **Position 4** `r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq -`
                          perft(1..5) = 6, 264, 9467, 422333, 15833292
- **Position 5** `rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ -`
                          perft(1..5) = 44, 1486, 62379, 2103487, 89941194
- **Position 6** `r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - -`
                          perft(1..5) = 46, 2079, 89890, 3894594, 164075551

Depth budget: 1..5 for all six is a few seconds native; startpos perft(6)=119M is the
heaviest single run (seconds). Keep the default gate to perft(1..4/5); perft(6) as an
opt-in deep check.

## The plan (mirror zlib/tcc)
1. **Vendor** a compact, portable-C, perft-capable engine via
   `tools/install_lib_candidates.sh` (gitignored source + PROVENANCE.md w/ upstream
   commit). Candidates, best-fit first:
   - **VICE** (bluefever tutorial engine, GPL) — ships perft + the standard positions;
     portable C, mailbox 0x88-ish, no libc math surprises. First choice.
   - **TSCP** (~2500 LOC classic) — clean but perft not shipped; add a ~30-line
     movegen-walk driver.
   - **micro-Max** (one file, ~130 lines) — ultra-dense C, great stress but hard to
     debug; keep as a torture follow-up, not the first target.
   Prefer an engine whose movegen is legal-move (or that you drive to legal perft), so
   the counts match the canonical values exactly (pseudo-legal perft gives different
   numbers).
2. **Runner + oracle:** `test/chess/perft_main.c` (or use the engine's own perft entry)
   that sets each FEN, runs perft(depth), prints `pos depth count`. `make test-chess-perft`
   compiles it with `$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src`, runs, and compares
   every count to the canonical table above (byte/number-exact). NO gcc oracle needed
   (but a gcc build is a cheap sanity cross-check for the harness itself).
3. **Blocker loop** (same as tcc): compile → run → any wrong perft count = a movegen /
   bit-op / recursion miscompile. Bisect to the construct, minimal repro **vs the
   canonical number** (or vs gcc for the isolated snippet), fix ONE thing, add a bXXX
   regression test wired into test-core, land green. Expect bit-shift/rotate, 64-bit
   mask, signed/unsigned edge, and array-of-struct movelist bugs — exactly the class
   sqlite/lua don't stress.

## Gate
`make test-chess-perft` = every canonical perft count matches (startpos + Kiwipete +
pos 3-6, depth 1..5). If the frontend/IR changed: `make test` + self-host byte-identical,
then `make stabilize && make pin` (verify VERSION advanced). Cross targets confirm via
Track T (watcher) — perft is deterministic, so a cross red = a real per-target bit bug.
Land only green; regression tests per fix.

## Landmines (from the tcc/00216 arc — DO NOT relearn)
- **No literal `{` / `}` in `{ }` Pascal comments** in compiler sources — desyncs the
  self-host lexer ("unexpected character"). Reword to prose.
- **No ErrOutput/writeln debug left in** before the byte-identical build.
- A 2-step self-host converge = the comment-brace landmine (reseed), NOT a real bug.
- `make stabilize` alone runs test-core (~2-3 min) — background it; then `make pin` and
  verify `compiler/pascal26 == stable_linux_amd64/default/pinned` + VERSION advanced.
- Perft mismatch is almost never "the engine is wrong" (canonical numbers are proven) —
  it's a pxx miscompile. Instrument the divide-perft (per-root-move subtotals) to bisect
  which move generation/count diverges, then minimal-repro that construct.

[[feature-c-corpus-expansion]] · [[feature-c-corpus-duktape]] · [[project_c_compound_literals_done_00216_residual]]

## COPY-PASTE KICKOFF PROMPT (fresh session)

You are Track A+C (compiler core + C frontend), on master, sole-A confirmed (you may
self-resolve shared-internals changes). Task: land the next C-corpus rung — a **chess
engine perft** corpus — per devdocs/progress/backlog/feature-c-corpus-chess.md (READ IT
FIRST; the canonical perft values, engine choice, and loop are settled there — do not
re-derive them).

VERIFIED CONTEXT (do not re-check): c-testsuite is 220/220/0, zlib/cjson/lua/sqlite green
byte-identical, tcc self-compiles and the pxx/gcc lineages converge (g3==p3) — the C
frontend is strong. Pinned binary is current (VERSION >= 189). The corpus ladder's next
rung is chess because perft gives a COMPILER-INDEPENDENT known-answer oracle (the numbers
in the ticket ARE truth) and it cross-validates the existing Rust chess perft.

Do this loop:
1. `git pull --rebase`. Confirm 220/220 still (`make test-c-conformance`) and pinned
   binary current (`cat stable_linux_amd64/default/VERSION`).
2. Vendor a compact, portable-C, perft-capable engine (VICE first choice; TSCP+own
   perft driver; micro-Max as torture follow-up) via tools/install_lib_candidates.sh —
   gitignored source + PROVENANCE.md (upstream commit). Prefer LEGAL-move perft so the
   counts match the canonical table exactly.
3. Wire `test/chess/perft_main.c` (or the engine's perft entry) + `make test-chess-perft`:
   compile with `./compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src`, run each FEN's
   perft(1..5), compare every count to the canonical table in the ticket. NO gcc oracle
   needed; a gcc build is just a harness sanity check.
4. Any wrong perft count = a pxx miscompile (movegen/bit-op/64-bit-mask/recursion/
   array-of-struct movelist), NEVER the engine (canonical numbers are proven). Use
   divide-perft (per-root-move subtotals) to bisect which move diverges → minimal repro
   vs the canonical number (or gcc for the isolated snippet) → fix ONE primitive → add
   test/cchess_*_bNNN.c (exit 42) wired into test-core → land green.
5. GATE per fix: repro matches; `make test-chess-perft` advances; `tools/testmgr.py
   --tier quick` + self-host byte-identical (compiler changed → `make stabilize` then
   `make pin`, verify VERSION advanced + compiler==pinned); test-lua green; cross via
   Track T (`tools/twatch.py --status`). Commit each fix separately with its regression
   test; push each unit; update this ticket's log; board-md.

LANDMINES (from the tcc/00216 arc — in the ticket, do not relearn): no literal { or }
in { } Pascal comments (self-host lexer desync); no ErrOutput/writeln debug in the
byte-identical build; a 2-step converge = the comment-brace landmine not a reseed;
`make stabilize` alone runs test-core (background it). When perft mismatches, instrument
the divide, don't guess.

After chess lands, the next rung is [[feature-c-corpus-duktape]] (JS engine, GC + float).
