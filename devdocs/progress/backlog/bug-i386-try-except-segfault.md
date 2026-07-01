# i386 target: `try...except` segfaults (layout-sensitive, not universal)

- **Type:** bug (i386 backend / exception machinery — correctness) — Track A
- **Status:** backlog
- **Severity:** high — a basic, single `try...except on E: Exception do` block
  can crash the i386 target outright (SIGSEGV), though it doesn't happen for
  every program shape (see below).
- **Opened:** 2026-07-01 (found while cross-verifying
  [[bug-except-base-handler-misses-derived]] on i386/arm32/aarch64 — confirmed
  pre-existing on the unmodified pre-fix binary, unrelated to that fix)

## Symptom

```pascal
program i386_one_block;
uses sysutils;
begin
  try raise Exception.Create('a'); except on E: Exception do writeln('c1'); end;
  writeln('done');
end.
```

Compiled `--target=i386` and run under `tools/run_target.sh i386`, this exits
139 (SIGSEGV) — no output at all, not even `c1`. Same result for:

```pascal
type EMy = class(Exception) end;
begin
  try raise EMy.Create('a'); except on E: EMy do writeln('c1'); end;
  writeln('done');
end.
```

and for two sequential (non-nested) `try...except` blocks in a row (using
`Exception` directly, no subclassing).

**But it is not universal** — this superficially-similar program does NOT
crash and prints correctly (`msg:` then `done`, though `E.Message` itself
comes back empty — a separate, also-pre-existing issue, see below):

```pascal
type EMy = class(Exception) end;
begin
  try raise EMy.Create('hello');
  except on E: EMy do writeln('msg:', E.Message); end;
  writeln('done');
end.
```

The only difference between the crashing and non-crashing minimal repros
above is the handler body's statement (`writeln('c1')` vs.
`writeln('msg:', E.Message)`) — i.e. this looks layout/code-shape-sensitive
(consistent with a stack-frame or exception-frame corruption bug whose
symptom depends on what happens to sit in the corrupted memory), not a clean
"any try/except crashes" defect. Each individual repro is **deterministic**
(same binary, same crash, every run) — it's cross-*program* variation, not
run-to-run flakiness.

## Confirmed pre-existing, not a new regression

Reproduced against the compiler binary from immediately before
[[bug-except-base-handler-misses-derived]]'s fix landed (pin v127) — this bug
predates that work and is unrelated to it. Filing separately since it's a
distinct defect (crash/memory-corruption vs. that ticket's handler-selection
logic bug).

## Related, separate observation: `E.Message` empty on all 3 cross targets

Independent of the crash: even in the *non*-crashing repro above, `E.Message`
prints as empty on i386/arm32/aarch64 (`msg:` with nothing after the colon),
while the identical program on x86-64 (native) correctly prints `msg:hello`.
This reproduces on the pre-fix v127 baseline too — a real, separate,
pre-existing cross-target defect (the exception object's `Message` field, or
its accessor, isn't reaching the raised value correctly on non-x64 targets).
Filing as a candidate follow-up in this ticket's scope note since both were
found together, but it may deserve its own ticket if picked up separately —
distinct symptom (wrong/empty data, not a crash), possibly a distinct root
cause (field layout vs. String/AnsiString ABI differences across targets).

## Scope

- Root-cause the SIGSEGV: narrow down what code-shape triggers it (start from
  the two contrasting minimal repros above — the presence of `E.Message` in
  the handler body seems to correlate with *not* crashing, which is a
  meaningful clue, not likely the actual fix).
- Decide (once root-caused) whether `E.Message`-empty is the same bug wearing
  a different hat, or truly separate.
- A cross-target (i386/arm32/aarch64) exception smoke test does not currently
  exist in `make test`/`test-i386`/`test-arm32`/`test-aarch64` — add one once
  fixed, covering at minimum: single try/except, sequential try/except blocks,
  and `E.Message` correctness.

## Acceptance

- Both minimal repros above (crashing and previously-"working"-but-wrong)
  run correctly on i386 under `tools/run_target.sh i386`, printing the
  expected output with no crash and a correct `E.Message`.
- Same coverage added for arm32/aarch64 (confirm `E.Message` there too — not
  independently verified as crash-free beyond the specific repros run this
  session, though no crash was observed on those two targets).
- Wired into the relevant cross-target `make test` targets.

## Log
- 2026-07-01 — Opened while cross-verifying an unrelated except-handler fix.
  Confirmed pre-existing on v127 (pre-fix) baseline via direct testing:
  i386 SIGSEGVs (exit 139) on a single basic `try...except` block in one
  code shape, runs clean in another; `E.Message` empty on i386/arm32/aarch64
  even where no crash occurs. Not investigated further — out of scope for
  the session that found it.
