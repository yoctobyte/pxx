# Handover 2026-07-03 — Track A, optimization arc (mid-flight)

You are **Track A (compiler)** on frankonpiler, working directly on `master`.
Read `CLAUDE.md` + `devdocs/dev/parallel-tracks.md` first. This handover
continues a session that ended mid-arc; the active ticket is
**`devdocs/progress/working/feature-optimization-levels.md`** — read it fully,
it carries the design, the measured baseline, and the pass queue.

## Where things stand (all pushed, tree clean, pin = v165)

- Pin path: `make stabilize-fast` (~18s, curated smoke + full self-host
  byte-identity chain) for iteration; FULL `make stabilize` before pushing a
  batch / milestones / anything touching codegen/ABI/ELF. `make pin` blesses.
  Policy in parallel-tracks.md.
- Self-compile: 10.4s → 5.5s via FindProc/FindSym hash indexes (done ticket:
  `perf-compiler-hotspots-algorithmic` — read its LANDMINES section before
  touching symtab). Allocator bins were measured and REJECTED (flat + made
  PXXFree 10x hotter); PXXAlloc heat = zero-loop + alloc count, belongs to
  codegen/-O, not the allocator.
- **-O plumbing landed**: `-O0..-O3` → `OptLevel` (defs.inc). -O0 = historic
  1:1 emission; the -O0 self-host byte-identity gate must stay untouched —
  every pass gates `OptLevel >= tier`.
- **Pass 1 landed (-O1, x86-64)**: leaf-const BINOP operand direct load
  (`mov rcx, imm` instead of push/eval/mov/pop). Register contract downstream
  identical (rax=left, rcx=right). Result: -O1-built compiler self-compiles
  16% faster (4.64s), binaries ~10% smaller, -O1 fixedpoint holds.
- **Gate**: `make test-opt` = 12-program differential corpus (-O0 vs -O1
  runtime output cmp'd) + -O1 self-compile fixedpoint. Also run full
  `make test` under an -O1-BUILT compiler when a pass changes (swap the
  binary, run, restore — see the session's pattern).

## Next work, in order (designs in the ticket)

1. **Pass 2: leaf-sym operand load** — extend pass 1 to `IR_LOAD_SYM` right
   operands of plain scalar locals/globals (load direct into rcx). CAUTION:
   only kinds whose IR_LOAD_SYM emission is a single side-effect-free load —
   check the IR_LOAD_SYM case for managed/frozen/float special paths and
   exclude them; the win is Integer/Int64/pointer loads.
2. **Pass 3: store-reload elimination** — `mov [slot],rax; mov rax,[slot]`
   at statement seams. Do it IR-side (IR_STORE_SYM followed by IR_LOAD_SYM of
   the same sym as next value use), NOT by rewriting emitted bytes (fixup
   positions reference CodeLen — never move emitted bytes).
3. xor-zero + inc/dec + imm-fold peepholes (size, mostly).
4. branch-over-branch (`jcc +2; jmp X` → `j!cc X`).
5. After 2–3 passes trusted: DECIDE flipping the pinned binary to -O1-built
   (free speed for tracks B/C; currently pins stay -O0-built).
6. Then the bigger tiers: `feature-inline-routines` (-O1/-O2, auto-inline
   design updated in that ticket) and `feature-callconv-register-args`
   (-O2 ABI flag-day, own ticket).

## Rhythm per pass

pass → `make test-opt` → full `make test` under an opt-built compiler →
hyperfine self-compile (record delta in ticket) → commit (small unit) →
`make stabilize-fast` + `make pin` for iteration / full `stabilize` before
batch push → push. Record every measured number in the ticket log.

## Working agreements with Rene (memory has these too)

- **Autoproceed.** Don't ask permission for the next queued step; pause only
  for destructive/scope-change decisions. He walks away and expects progress
  + periodic pins/pushes.
- **Answer questions in a tool-free turn.** His client drops text from turns
  that also run tools (Fable 5 display issue; may or may not affect Opus —
  keep the habit until confirmed). Answer standalone, THEN resume work next
  turn.
- Chained `commit && make stabilize && push` mega-commands hide progress for
  minutes — run slow steps as separate visible commands.
- "Small fix" promises: he knows 9/10 hide skeletons; scope honestly.

## Landmines (hard-won this session)

- **Never edit `compiler/**` while a background make runs.**
- The 386 IR walker's `else IREmitNodeXtensa/386(i)` fallback DOUBLE-EXECUTES
  value-producing ops not in its operand skip list (x86-64 whitelists
  statements instead). New IR op ⇒ add to every 32-bit walker's skip list.
- Grep for assignment sites with `\s*:=` regexes — `SymCount  := savedSC`
  (two spaces) cost hours.
- Symtab hash: inserts happen at the `Inc(SymCount)` visibility point; scope
  exits MUST go through `SymRollbackTo` (never assign SymCount directly).
- `make test` output pipes hide failures mid-stream; check exit codes.
- hyperfine for all measurements (warmup 2+, runs 5); `--proc-map` flag +
  perf for profiles (recipe in the closed hotspot ticket).

## Board state

`working/`: feature-optimization-levels (active).
Recently done (same day): perf-compiler-hotspots-algorithmic,
chore-fast-pin-tiered-tests, feature-i386-threadsafe-locks,
bug-method-call-before-body-byvalue-small-record-arg, the 9-ticket batch
(v159), managed-record dynarray Insert/Delete + IR_CONST_DATA (v162).
Backlog highlights for later: dynarray nested-element remainder,
feature-inline-routines, feature-callconv-register-args,
bug-c-cast-as-call-arg-parse-error.
