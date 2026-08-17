# Differential probes — the bug generator

Four standing harnesses that run small programs under pxx **and** under a
reference implementation, diff the output, and report divergences. They are the
most productive bug-finding method in this repo: the night of 2026-08-05, five
of seven fixed bugs came from adding case batches to two of them, including two
silent-wrong-value bugs in the backends.

This page is the **index and the shared rules**. Each script's own header is the
authority on its specifics and is worth reading before you add to it — they
record traps that cost real sessions.

## The four

| tool | oracle | answers | lane that owns the TOOL |
| --- | --- | --- | --- |
| `tools/fpc_diff_probe.sh` | FPC | does our Pascal agree with FPC? | B |
| `tools/gcc_diff_probe.sh` | gcc's libc | does our C / crtl agree with gcc? | B |
| `tools/pydiff.py` | CPython | does NilPy agree with CPython? | N |
| `tools/lib_cross_sweep.sh` | **pxx on x86-64** | does a cross target agree with the native build? | B |
| `tools/crtl_decl_probe.sh` | — (census) | is a declared crtl function actually IMPLEMENTED, or silently binding to libc? | B |

`crtl_decl_probe` is the odd one out: it has no oracle. It answers *"is the
symbol there at all"*, which is the question **before** `gcc_diff_probe`'s
*"does it agree"*. A function can produce correct values for months while
quietly pulling in `libc.so.6` — `clock_gettime` did. `readelf -d` is the check;
that script automates it.

`lib_cross_sweep` is also not a parity probe: its oracle is **our own** x86-64
output, which `lib-test` already proves green. Anything a cross target prints
differently is a target-dependent bug.

**Fuzzers** (`tools/fuzz.sh`, `tools/pasmith*.py`, Csmith) are the same idea with
a generated corpus instead of a curated one, and they belong to Track T — see
`devdocs/dev/track-t.md`.

## The rules every one of these shares

These are not style preferences. Each was learned by chasing a phantom.

**1. When the ORACLE looks wrong, it is the harness.** gcc segfaulting, FPC
printing garbage, CPython raising — none of those is a pxx bug. Check that
first; it is always quick.

**2. Never read a side effect in the argument list of the call that causes it.**

```c
printf("%d [%s]", fread(b, 1, n, f), b);      /* WRONG */
```

Argument evaluation order is unspecified, gcc goes right-to-left, and **pxx
orders arguments differently on arm32/aarch64 than on x86-64** — all legal. This
shape produced four separate phantom bug reports in one session. Sequence the
call, then print.

**3. A skip is not a pass.** A case the oracle cannot build compared nothing.
Both shell probes count and print skips for exactly this reason: one missing
`uses` silently disarmed two exception cases for months while looking like
coverage.

**4. Read the summary line, not the DIFF lines.** `grep -v '\[known\]'` has twice
produced a confident "0 new" while the summary said otherwise.

**5. Never edit a probe by slicing between markers.** A Python slice-edit once
deleted a block of cases; the tell was the run reporting 1 known where it had
reported 13. Append at the summary anchor.

**6. Compare FULL outputs when A/B-ing a sweep.** Two traps, both hit on
2026-08-05: a baseline built from `tail -25` of a 37-line report read as a huge
regression, and `comm -23` against a run that was killed part-way reports every
*unreached* test as "fixed". Restrict the comparison to the range actually
covered, or re-run.

**7. Network and thread tests under qemu flake.** `lib_platform_esp`,
`lib_sockets` and `lib_net_v6only` each flip verdict run-to-run with the *same*
compiler. Before believing one, re-run it with the pinned stable AND your build
— see `bug-t-three-network-tests-flake-and-cost-real-debugging-time`.

## Tags

A case that diverges for a filed, understood reason is tagged so a clean run
shows only NEW findings:

| tag | meaning |
| --- | --- |
| `known` | a filed divergence. Keep the case — it starts reporting again the day it is fixed, and the semantics stay under test meanwhile |
| `lp64` (gcc probe) | output legitimately depends on the data model (`long` width); not judged under `--target` |
| `charsign` (gcc probe) | output depends on whether plain `char` is signed — it is on x86-64, unsigned under the ARM PCS. Not a divergence |

**A `known` tag can hide a second bug behind the first.** `thread-critical-section`
was tagged for a compile failure; when that was fixed the case ran and exposed
`TCriticalSection` being a no-op stub — silent lost updates. When you fix the
reason for a tag, *untag and re-run* before assuming the case is now green.

## Adding a case

Ten seconds, and it is the whole point of the harnesses:

```sh
probe <name> [known|lp64|charsign] <<'P'
uses SysUtils;
begin
  writeln(Format('%n', [1234567.5]));
end.
P
```

The shell probes prepend the program header, build both sides, diff, and count.
Pick an area nobody has covered and write ten cases — that is what found the
aarch64 comparison bug (integer promotion), the 32-bit virtual-call bug (via the
cross sweep) and the whole threading batch.

Areas with no coverage as of 2026-08-05: `Currency` beyond arithmetic, variant
records, `array of const` past the basics, class helpers (blocked on the
parser), and on the C side `volatile` / `restrict` / bitfields-in-unions.

## Whose bug is it

**The probe owns the TOOL, never the bug** — the same rule Track T runs on. A
finding is filed into the lane that owns the code: IR/codegen/backends → A,
Pascal dialect → P, RTL/crtl → B, NilPy → N, C frontend → C. Tonight's batch
produced tickets in A, P and B from two B-owned probes, which is the normal
outcome and not a sign the lanes are wrong.

## Where else these are mentioned

`devdocs/dev/debugging-playbook.md` (step 1 — which tool, in which order) and
the tool table in `CLAUDE.md`. Ticket write-ups cite them constantly; those are
history, not instructions — this page and the script headers are the live docs.

## Hygiene: a differential that overwrites one of its own arms LIES TO YOU

Recorded 2026-08-17, Track A, while chasing the Synapse TLS crash.

The FPC control was built as `sslprobe` — **the same output name as the pxx
binary**. The next three `LD_PRELOAD` experiments then "proved" that preloading
libcrypto fixed the crash. They were running the FPC build.

The failure mode is worse than a wasted hour: **it reads as a discovery.** The
experiment produces a clean, consistent, repeatable result that points somewhere
plausible and wrong, and nothing about the output says which binary produced it.

**Rule: distinct output names from the very first command**, e.g. `probe.pxx` and
`probe.fpc`, never a bare shared name you intend to rebuild. If a probe script
takes an oracle flag, make it name the artefact after the oracle.

Same family as "to count how many times something ran, the observable must live
outside the thing being counted" — in a differential, the evidence must sit
outside the arm being varied. See also the standing rule that any reported result
names the sha of the binary it came from.

**Adjacent Pascal trap from the same session:** a brace comment does **not** nest,
so `{$MODE DELPHI}` written inside `{ ... }` as documentation is a **live
directive**. Documenting a mode table in a `.pas` comment will change the mode or
fail the parse. Use a spelling the preprocessor cannot read.

## A probe that FORMATS its output can answer a different question than you asked

Recorded 2026-08-17, Track B, twice in one night by the same session.

A boundary table was built by a probe piping each case through `head -1`. On the
rows where the module-level statement was a `print`, **the print's own output was
the first line** — so what got recorded as "the attribute reads correctly" was
really "the print ran". The attribute value was never in the captured output at
all.

The framing that makes it memorable: **those rows were not mismeasured, they were
unmeasured and labelled.** A mismeasurement is a wrong number; this produced a
number that was never about the subject, and the table looked complete.

Earlier the same night, the same lane's corpus scan died on strict UTF-8 decoding
because a diagnostic can echo a source line and the corpora carry non-UTF-8 bytes —
a scan that stops at the first odd byte is also its own artefact. Fixed with
`errors="replace"`.

**Rule: the capture step is part of the instrument.** `head`, `tail`, `grep -h`,
`| head -1`, strict decoding, and "first line of output" are all places where the
harness quietly changes the question. When a row of a boundary table surprises you,
check what the harness captured before checking what the compiler did — and prefer
labelled output (`K.A 7 J.A 0`) over positional output, so a shifted line cannot
masquerade as a value.

Related: `grep -h` suppresses filenames, which silently defeats a downstream
`grep -v /tests/` filter — same lane, same night, different pipe.
