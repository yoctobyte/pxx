---
track: D
prio: 45
type: bug
blocked-by: []
summary: "`tools/docsnip.py` compiles docs/** snippets against the PINNED compiler, and three of them now fail with `unknown type: TMethod` — inside lib/rtl, not inside the snippet. `a623307bd` made TMethod a builtin and deleted the RTL duplicates, so the pin's compiler cannot build the current RTL at all. Nothing is wrong with the three documents; Track D's only gate is red for every session until the next pin. Second aperture hole found 2026-09-05: the completeness test is `^program`, so a `library` snippet is invisible to the gate entirely — and the pin rejects `library` at token 1 anyway."
status: done
owner: frankD
---

# The docs snippet gate cannot pass: the pin predates `TMethod` becoming a builtin

```
$ python3 tools/docsnip.py
docsnip: 200 code blocks, 39 complete Pascal programs, 161 fragments/other
  compiled or failed-as-documented: 30   BROKEN: 3   skipped: 6
  BROKEN  docs/library/json.md:49         pascal26:413: error: unknown type: TMethod
  BROKEN  docs/library/networking.md:13   pascal26:413: error: unknown type: TMethod
  BROKEN  docs/library/networking.md:92   pascal26:413: error: unknown type: TMethod
```

`pascal26:413` is a line in a **library unit**, not in any snippet.

## The three documents are fine

Extracted `docs/library/networking.md:13` verbatim and compiled it both ways at
`9bcfd2b4da30`:

| | result |
|---|---|
| HEAD | `ok: … [code=1351448B …]` |
| `stable_linux_amd64/default/pinned` | `near: m : TMethod ; begin m >>> . Code :=` |

`a623307bd` — *"System.TMethod is declared once — delete the RTL duplicates, and
let a UNIT see the builtin"* — moved `TMethod` into the compiler and removed the
declarations `lib/rtl` used to carry. The pinned compiler has no builtin
`TMethod` and the RTL no longer declares one, so **the pin cannot build the
current RTL**, and every snippet that reaches it fails.

## Why this is worth a ticket and not a shrug

**A gate that cannot pass is not a gate.** Track D's gate is "compile the
snippets against `$(PXX_STABLE)`" and it is the only one D has. Red for a reason
no doc change can fix means the next D session either reads three permanent reds
as background noise — and then misses a real fourth — or spends the same
half-hour re-deriving this.

It is also the mirror of the trap `$(PXX_STABLE)` guidance already warns about:
the known hazard is a snippet PASSING under the pin for a reason unrelated to
the change. This is the same mechanism pointing the other way, and it is louder,
so it is the easier half to catch — but only once.

## Options, none of them Track D's to pick

1. **A new pin** picks it up for free. Track A, blocks everyone while it runs,
   and there is a green-vs-reds grading question that is not mine.
2. **`docsnip.py --head`** — an opt-in arm for exactly this window, red-flagged
   in its own output so nobody quietly makes it the default. Track T owns the
   tool.
3. **Leave it and record the three** so a fourth is visible. Cheapest, and what
   this ticket does in the meantime.

Found 2026-09-05 by frankD (Track D) while gating the `{$MODE}` dialect-scope
doc update — which added no snippets, deliberately, because the pin cannot
demonstrate the behaviour being documented either.

## 2026-09-05 — the same gate has a second hole, and it is an APERTURE one

Documenting `library`/`exports` in `docs/reference/objects.md` I hit the other
end of the same problem. `docsnip.py`'s completeness test is

```python
if lang not in ('pascal', 'pas') or not (
        re.match(r'^program\s', t) and t.rstrip().endswith('end.')):
```

so a block whose header is `library` is classified as a **fragment** and never
compiled. It does not error and it does not skip-with-a-reason; it is counted in
`fragments/other` alongside the genuine one-liners. The gate reports the same
green whether the snippet is correct or nonsense.

The two holes compound rather than cancel. Even if the completeness test grew a
`library` arm, the pinned compiler answers, measured at `9bcfd2b4da30`:

```
$ stable_linux_amd64/default/pinned mylib.pas mylib.out
pascal26:1: error: expected 'begin' before 'library'
```

`library`/`exports` landed 2026-09-04, after the pin. So there is **no pinned
compiler that can check a `library` snippet**, and widening the aperture without
a new pin converts a silent gap into a permanent red — which is option 1 above,
again, and still Track A's call.

Meanwhile the snippet now in `objects.md` is hand-verified at HEAD `ce19e5482`
(binary `9bcfd2b4da30`) and the document says so. That is the honest handling,
not a substitute for the gate: the next person to edit that block gets no
warning from `docsnip.py` at all.

## 2026-09-05 — the census, measured, and the list a D session actually needs

frankH found the scope and frank-coordinator relayed it; I re-measured rather
than relaying, because the actionable artifact here is the exact unit list and
an approximate one sends someone to "fix" a snippet that is fine.

Compiled `program t; uses <U>; begin end.` for each of the 111 `lib/rtl/*.pas`
units against `stable_linux_amd64/default/pinned`:

- **83 compile.**
- **24 fail with `unknown type: TMethod`** — and this is the outage:

  `ast atexit base64 classes_lite configparser dns_resolved http httpjson io
  json lfm markdown mimic_codecs mimic_string mimic_urllib_error
  mimic_urllib_request pathlib re resources streams subprocess tls13_native
  truststore typinfo`

- **4 fail for something else and are NOT part of this** — `palparallel`,
  `palpthread`, `palthread`, `palthreadobj` answer *"`__pxxclone` (thread
  creation) requires `--threads`"*. They answer the same at HEAD and compile
  with `--threads` at both, so that is a correct refusal, not the pin.

**Splitting those four out is the point of re-measuring.** A raw "28 units fail
under the pin" is true and would have been recorded as the blast radius of one
cause; it is two causes, and only one of them expires with the next pin.

Ancestry confirmed independently with `git merge-base --is-ancestor`: pin v403
is `ce63beeeb`, and both `31f8b11bf` (TMethod as a builtin) and `a623307bd`
(delete the RTL duplicates) are its descendants.

**For whoever is next in `docs/**`:** if a snippet stopped compiling, check its
`uses` clause against the 24 above before touching the snippet. `sysutils`,
`math` and `classes` are all fine. A snippet that names one of the 24 is correct
and the instrument is not — verify it with `compiler/pascal26` at HEAD instead,
and say in the commit that you used HEAD and why, so the claim expires by
itself.


## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 36ee694fa.

## 2026-09-05, later — pin v404 closed both halves, and one aperture stays open by design

`8844c8c42`, binary `fe1e9c37d322`, tree `5b5fdb0b3`. Both problems this ticket
recorded are gone, and they went for different reasons.

**The TMethod half: fixed by the pin, as predicted.** `docsnip.py` now reports
**BROKEN: 0** where it reported 3 all day. The 24 units are unblocked. Nothing
in `docs/**` was edited to achieve that, which was the point of recording it
rather than "fixing" the three documents.

**The aperture half: `library` is now checkable, so it is checked.**
`7763e1df6` (the `library`/`exports` feature) *is* an ancestor of the pin tree —
confirmed with `merge-base --is-ancestor`, and confirmed again by compiling the
snippet: pin v404 accepts `library` where v403 answered `expected 'begin' before
'library'` at token 1. So widening the completeness test no longer converts a
silent gap into a permanent red, which was the only reason not to. It is
`^(program|library)` now, and `docs/reference/objects.md:105` moved from
`NOT CHECKED` into the compiled population: 40→41 complete programs, 34→35
compiled.

**`unit` stays reported and that is not a deferral.** A bare unit cannot be
compiled at all — pxx answers *"this file is a unit, not a program — compile a
program that uses it"*, which is correct. Checking one would mean generating a
host program around it, which is exactly the inventing this tool's own docstring
refuses to do. So the count is the tell, permanently, and the line names the file
and line of anything that appears.

**Zero census, so the probe was proven live rather than assumed.** With the
`library` block promoted there are no `unit` blocks left in `docs/**` and the
`NOT CHECKED` line disappears entirely — indistinguishable from a detector that
stopped working. Controlled twice: seven classifier rows including `unitfoo :=`
for the word boundary and a non-pascal fence, and end-to-end by planting a real
`unit` block in `docs/reference/limits.md`, confirming it was reported with the
right file and line, and removing it (`git diff` empty afterwards).

**Also re-verified rather than assumed: the six scope-claim rows from
[[bug-d-docs-scope-claims-about-a-flag-are-invisible-to-a-flag-existence-sweep]]
were measured against v403 and are byte-identical under v404.** frank-coordinator
asked whether a pin fires that ticket's re-run trigger. It does not by the letter
— a pin is neither a new backend nor a new target-scoped flag — but the rows had
been measured *with* v403, and a new pin is a new instrument. Re-running the
table cost under a minute and settles it instead of arguing it, which is cheaper
than the question. The `--shared` internal-error defect reproduces under v404 too.

