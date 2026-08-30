---
track: B
prio: 40
type: feature
blocked-by: []
summary: "Campaign: differential-test the mimic_ shims against CPython, after a two-shim pilot returned five findings including a SIGSEGV. Phase 1 is the codecs differential — the only shim with real surface and NO differential — whose encode half is blocked by bug-b-codecs-encode-segfaults-for-every-encoding-except-utf-8. Phase 2 is edge-coverage spot-checks on the already-covered shims, not re-testing their happy paths."
status: backlog
owner: unassigned
---

# Sweep the `mimic_` shims against CPython

- **Type:** feature (library, testing) — **Track B**.
- **Filed:** 2026-08-30 by frankB, after a dispatched pilot over two shims was
  stopped early because the yield made it a campaign rather than a sweep.
- Everything here builds with `$(PXX_STABLE)`; no compiler rebuild.

## Why this is a campaign and not a chore

Every `mimic_` shim was written from CPython's **prose documentation** by
sessions that mostly could not run a diff. The prose describes the success path;
it is systematically silent about malformed input, empty input, ordering, and
whether an error fires before or after a lookup. That is exactly where the
pilot's findings were.

**Pilot: two shims, five findings.**

`urllib.parse` (fixed, `4b4f6...`-adjacent commit on 2026-08-30):

1. **A gate that was claimed but never written.** The shim's header cited
   `test/lib_mimic_urllib_parse.npy` as its differential. No such file existed
   and none ever had — checked the *history*, not just the tree. 232 lines
   asserting coverage they did not have. **That is worse than no gate: a file
   with no differential invites one; a file that says it has one does not.**
2. `urlunsplit` open-coded a condition that never consulted `uses_netloc` — a
   list the module did not define, while its sibling `uses_params` was present
   and correct. **9 of 20 tuples wrong** (`mailto:///a@b`,
   `data:///text/html,x`, relative paths silently rewritten absolute), and
   round-tripping broken for every scheme outside `uses_netloc`, against a
   header advertising the inverses as the same grammar walked backwards.

`codecs` (filed, not fixed):

3. [[bug-b-codecs-encode-segfaults-for-every-encoding-except-utf-8]] — **SIGSEGV**
   for ascii and latin-1 on every input including the empty string.
4. [[bug-b-codecs-strict-decode-does-not-raise-on-invalid-utf-8]] — all three
   error policies behave as `replace` on the utf-8 path.
5. [[bug-n-a-lambda-returning-a-captured-heap-value-yields-none]] — Track N,
   found because it corrupted the probe (see the instrument warning below).

## Phase 1 — the `codecs` differential

`lib/rtl/mimic_codecs.pas` is 574 lines with **no differential at all**, and it
is where a total crash in two of its three encodings sat unnoticed.

Cover: `encode` / `decode` × `utf-8` / `ascii` / `latin-1` × `strict` /
`replace` / `ignore`, plus `lookup` (including `LookupError` for an unknown
name and the `utf-8` / `UTF-8` / `utf_8` aliases, which already pass), the
charmap trio, and the BOM constants. Byte-for-byte diff against CPython, in the
shape of `test/lib_mimic_urllib_parse.npy`.

> **The `encode` half is BLOCKED by finding 3 and must not be written around.**
> A differential that cannot run against half its subject will quietly test one
> direction and be reported as green — which is finding 1 all over again, in the
> gate rather than in the header. Fix the segfault first, or land the decode
> half with the encode half **explicitly absent and named as absent** in both
> the test's docstring and the Makefile comment. Do not let a green
> `MIMIC-CODECS OK` stand for "codecs works" while `encode` is untested.

**Why that blocker is prose and not a `blocked-by:` edge.** It blocks the
**encode half**, not the campaign. A frontmatter edge would make the whole
ticket unclaimable and park the decode half and all of phase 2 behind a crash
they do not depend on — the ranker reads `blocked-by` as "do not claim", with no
notion of partial. The constraint is real and load-bearing, so it is stated
where whoever writes the test will actually be standing, in a block they cannot
skim past. If the segfault is fixed first this paragraph simply stops applying.

`mimic_urllib_error.pas` (192 lines) also has no dedicated differential, though
unlike `codecs` it is exercised indirectly by the `urllib_request` suite. Lower
priority than `codecs` for that reason, but worth a pass in this phase.

## Phase 2 — edge coverage on the already-covered shims

**Not** re-testing happy paths. For each shim that already has a differential,
ask only: does it push the region the prose is silent about? Both pilot findings
were there, and one of them (`ValueError` raised *even when the name resolves*)
is the shape documentation never describes, because it is not on the success
path.

**Check count is a bad proxy for coverage, measured.** `lib_mimic_warnings.npy`
looked like the worst ratio in the tree (125-line shim, 1 match) and is
actually *well* reasoned: it asserts the shared contract, and its header states
which divergences are deliberately unasserted and why —
`catch_warnings(record=True)` is refused precisely so it cannot silently return
an empty list that reads as "no warnings were raised". Read the header before
judging a shim thin.

Candidates, ranked by edge-richness rather than by size:

| shim | why |
| --- | --- |
| `mimic_xml_sax_saxutils` | `escape`/`unescape`/`quoteattr` — quote selection, `&` ordering, and which entities are handled are classic silent-divergence ground |
| `mimic_copy` | `copy` vs `deepcopy` aliasing, nesting, shared sub-objects — 13 checks for semantics whose whole content is aliasing |
| `mimic_bisect` | `lo`/`hi` bounds, duplicate keys, `insort` position among equals — off-by-one country |
| `mimic_xml_etree_elementtree` | largest `.py` shim; the pilot's minidom work suggests tree mutation is where these drift |

**`mimic_colorsys` is Track F and stays low.** Its subject is float conversion,
so accuracy findings there are F by definition and parked, not ranked. A
**crash** or a wrong *signature* in it would still be an ordinary bug.

## Method

- Drive the shim and CPython over the same inputs, diff **byte-for-byte**; the
  `.npy` must run unmodified under `python3`.
- Assert only what the two AGREE on. A deliberate divergence goes in the
  header, never in an assertion — asserting a difference makes the file fail
  under one interpreter, which is the property that makes it worth having.
- Report negatives. "These six shims agree with CPython on N checks each" is a
  real result: it distinguishes *clean* from *unswept*. Keep skips separate
  from passes.
- Route by owner: a shim behaviour that is ours → **B**; a frontend gap → **N**;
  a compiler gap → **A/P**.

## Instrument warning — read before writing a probe

**Use `def`, not `lambda`, in NilPy probes** until
[[bug-n-a-lambda-returning-a-captured-heap-value-yields-none]] closes.

The pilot's first `codecs` probe was table-driven with `lambda` thunks. The
bytes-valued rows returned `None` and produced a complete, self-consistent and
**entirely wrong** finding — *"`codecs.encode` returns None for every
encoding"* — which was ready to file. Re-probing with `def` showed `encode` is
fine for utf-8 and **segfaults** for ascii and latin-1. The broken instrument
did not merely give a wrong answer: it gave a *milder* wrong answer that
**concealed a crash**.

The lambda ticket also records which green results are meaningless:
`sorted(key=lambda p: (a, b))` still sorts correctly, because the tuple is
*consumed, not returned*. A naive "do lambdas work?" check passes and is not
evidence of absence.

## Gate

Per shim: a `.npy` differential byte-identical under both interpreters, wired
into `lib-test` with its check count pinned. The campaign closes when phase 1
lands and phase 2's candidates have each been either extended or explicitly
recorded as already sufficient — with the reason, so the next sweep does not
redo the judgement.
