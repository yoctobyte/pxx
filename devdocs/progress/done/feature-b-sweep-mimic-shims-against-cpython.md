---
track: B
prio: 40
type: feature
blocked-by: []
summary: "Campaign: differential-test the mimic_ shims against CPython, after a two-shim pilot returned five findings including a SIGSEGV. Phase 1 is the codecs differential — the only shim with real surface and NO differential — whose encode half is blocked by bug-b-codecs-encode-segfaults-for-every-encoding-except-utf-8. Phase 2 is edge-coverage spot-checks on the already-covered shims, not re-testing their happy paths."
status: done
owner: frankB
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


---

## Phase 1 progress log (frankB)

### `codecs` — DONE, 2026-08-30

`test/lib_mimic_codecs.npy`, **83 checks, byte-identical**, wired into
`lib-test`. Both directions covered in one pass, which is why the segfault had
to be fixed first.

Three defects, all in `lib/rtl/mimic_codecs.pas`:

1. [[bug-b-codecs-encode-segfaults-for-every-encoding-except-utf-8]] —
   **SIGSEGV** on ascii and latin-1 for every input including `b''`. A Variant
   hard-cast to a class; grep found exactly two sites, both local.
2. [[bug-b-codecs-strict-decode-does-not-raise-on-invalid-utf-8]] — the
   "validity walk" the header described did not exist. `Utf8Decode_` was a pure
   byte copy that was not even PASSED `errors`, so all three policies behaved
   as `replace` and `strict` — CPython's default — never raised. Replaced with
   a real validator including the **maximal-subpart** replacement counts, which
   is the half that would have shipped wrong: right verdict + wrong count
   passes a naive test and corrupts every `replace` decode.
3. **BOM constants had the wrong TYPE** — `AnsiString` where CPython has
   `bytes`, so `data.startswith(codecs.BOM_UTF8)` answered False for data that
   begins with a BOM. `BOM_UTF8` doubly so: `#$EF#$BB#$BF` is a well-formed
   encoding of U+FEFF, so as a string it held ONE character and `len()` said 1
   where CPython says 3. No ticket of its own — found and fixed inside (2).

Routed out of the lane: [[bug-n-a-lambda-returning-a-captured-heap-value-yields-none]],
[[bug-n-the-hex-string-escape-emits-a-raw-byte-not-a-code-point]],
[[compat-n-repr-does-not-escape-non-printables-above-u007f]].

### `urllib.error` — DONE, 2026-08-30

`test/lib_mimic_urllib_error.npy`, **42 checks, byte-identical**, wired into
`lib-test`. This shim's only prior coverage was **indirect**, through the
urllib_request suite — which pins the paths request happens to take and
nothing else. Both findings were outside those paths, which is the argument
for the gate rather than an accident of it.

1. **`URLError.filename` was `''` where CPython leaves it `None`** — a
   filename that IS the empty string rather than no filename at all. Invisible
   to `if e.filename:`, visible to `e.filename is None`. Fixed: the field is a
   `Variant` holding `pynone`.
2. **The shim's header claimed something false about its own `__str__`
   methods** — that they "are what makes the common arm right today". Measured:
   the common arm is exactly what they do not cover. Corrected in place.

Both findings are the same shape as the pilot's finding 1: **prose asserting
coverage that was never measured**. That is now three of three shims where the
header's own claims were the productive thing to test first — the sentences a
past session thought worth writing down mark where it was least sure.

**No new ticket for the string-model rows** found on the way (a str-typed
`None` renders as `''` through `str`/`repr`/format/containers, and only `is`
sees it). That is the decided-but-partly-unbuilt NilPy string model; a fourth
re-ask is explicitly warned against on
`decided/decide-nilpy-none-str-sentinel-vs-textstr-kind`, so the measurement
is **recorded on that page's residual list** instead. Read it before reaching
for `pystr_none` in a shim — a `Variant` holding `pynone` is exact where
`pystr_none` gets eight of nine rows wrong.

**One divergence is left unasserted and named**:
[[bug-n-str-of-a-pascal-declared-exception-ignores-str-when-caught-as-a-base]]
— `except URLError as e: str(e)` on an HTTPError drops the status code. The
existing ticket recorded the `except Exception` case; this pass added the
**intermediate-class** case, which shows the dispatch is genuinely static
rather than a fallback, and recommended p60 without touching Track N's number.

**Phase 1 is complete.** Both shims that had no differential now have one.

### Phase 2 — DONE, 2026-08-30. All four candidates.

Not re-testing happy paths: for each shim that already had a differential, the
only question was whether it pushed the region its prose is silent about.
**Three of four had a defect there, and it was the same region every time —
the parameter or the argument, never the algorithm.**

| shim | checks | outcome |
| --- | --- | --- |
| `saxutils` | 18 → 45 | `quoteattr` merged the caller's `entities` **over** the three whitespace ones; CPython merges them **under** |
| `copy` | 13 → 35 | clean as a shim; surfaced a **frontend** bug |
| `bisect` | 18 → 50 | `hi` is a **sentinel at -1**, not a sign test |
| `etree` | 56 → 83 | **clean** — nothing found, and that is the result |

**saxutils.** CPython writes `{**entities, "\n": "&#10;", ...}`, so the three
come LAST and override the caller. Ours seeded with the three and let the
caller overwrite them — the obvious way round, and wrong: numeric escaping of
`\n`/`\r`/`\t` is not a default, it is the invariant that makes an attribute
value survive a parser's normalisation, and CPython refuses to let it be
switched off. Also pinned three CPython **quirks** so nobody "fixes" them:
`escape("a&b", {"&": "X"})` is the mangled `"aXamp;b"` in both; `unescape`
knows three entities and not `&quot;`/`&apos;`/numeric refs; the whitespace
three are not overridable.

**bisect.** The `-1` default was not an invention — CPython's `bisect` is the C
`_bisect` module, whose argument clinic defaults `hi` to `-1` and does
`if (hi == -1) hi = len(list)`. But the shim tested `hi < 0`, making every
negative mean "the end". `bisect_right([1,2,2,2,3], 2, 0, -2)` was 4 here and 0
in CPython. One character. The old docstring reasoned *"a negative hi is not
meaningful for this function otherwise"* — almost right, and it conflated `-1`
with negative, which is the kind of nearly-correct sentence a differential
exists to catch.

**etree came out clean and that is a real result.** Its 27 new checks cover the
mutation surface a treebuilder leans on (`extend`, `__setitem__`, `insert` at
both ends and out of range, `remove`'s raising arm) and qualified tags at a
**second** path step — the actual case the brace-aware splitter exists for,
which a single qualified step cannot exercise. Everything agreed. The shim was
right; the file now says so under test rather than by assertion in its header.

### Two frontend bugs, both found by writing fixtures rather than by testing

Neither is in a shim, and neither would have been reachable without trying to
write ordinary Python against one:

1. [[bug-n-tuple-unpacking-of-an-inline-tuple-does-not-unpack-iterable-values]]
   (N, p65). `a, b = Element("a"), Element("b")` binds **both** names to the
   whole right-hand list. Triggered by the value type declaring `__iter__` or
   `__getitem__` — `__len__` alone is fine — and only for an **inline** tuple:
   `a, b = tup`, `a, b = f()` and for-loop targets are all correct. **The swap
   idiom `p, q = q, p` is hit.** Silent; a longer program built on it
   segfaults. Sibling of the existing
   [[bug-n-a-tuple-unpacking-assignment-does-not-box-a-callable-value]] — same
   statement, different value kind, two defects in one construct, so grep for
   the other before closing either.
2. [[bug-n-len-does-not-dispatch-len-dunder-on-a-dynamically-typed-value]]
   (N, p60). `len(x)` raises whenever `x`'s static type was not inferred —
   `lst[0]`, `d["k"]`, an unannotated parameter, or the return of any
   **self-referencing** def, recursion included. On the same value `.attr`,
   `.method()`, `for`-in and `x[i]` all dispatch fine, so `len` is the one
   protocol with no dynamic fallback — and iteration already got exactly this
   fix in [[feature-nilpy-for-loop-getitem-protocol-fallback]]. One concept,
   two paths, second one broken.

Both are written around **loudly** in the etree differential — separate
fixture statements, and `len()` of a Comment left unasserted — with the reason
named in the file and in the Makefile, so the workaround cannot be tidied away
by someone who does not know why it is there.

## Disposition

**Campaign complete.** Six shims swept (2 in phase 1 with no gate at all, 4 in
phase 2 with a thin one), **125 new checks in phase 1 and 88 added in phase 2**,
every file byte-identical under both interpreters and wired into `lib-test`
with its count pinned.

**Findings: 5 in Track B (all fixed), 6 routed to Track N, 1 recorded on a
decided U ticket.**

### What the sweep learned, for whoever runs the next one

**Test the header's claims first.** Three of three phase-1 shims and two of
four phase-2 shims had their defect exactly where a past session had written a
confident sentence: a gate that was cited and never existed; `__str__` methods
claimed to "make the common arm right" when the common arm is what they miss;
a "validity walk" that was not there; "a negative hi is not meaningful"
conflating -1 with negative. The sentences a past session thought worth
writing down mark where it was **least sure**, and they are the cheapest
possible ranking of where to look.

**Rank by parameter, not by size.** Every phase-2 defect was in a
*parameter* — `entities`, `hi` — and none was in an algorithm. The shims'
algorithms were all correct. Check counts were a bad proxy (recorded above for
`mimic_warnings`); "which argument does the prose describe least?" was a good
one.

**Writing the test finds frontend bugs that reading it never would.** Both N
bugs above came from building fixtures in idiomatic Python, not from any
assertion. That is an argument for writing differentials in the ordinary
style and only then working around what breaks — loudly.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
