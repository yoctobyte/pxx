---
slug: bug-a-test-object-value-type-is-red-on-borg-and-green-on-plexus
title: "test_object_value_type is red on borg and green on plexus — an old-style object value type, host-dependent"
type: bug
track: A
prio: 55
status: new
created: 2026-09-18
owner: ""
summary: "`test-core#src:test/test_object_value_type.pas` has been RED in every native-tier tstate report since 2026-09-17T16:06 (cc03b4a, 19 reports), and the same test at HEAD passes by hand on plexus — rc=0, last line `OK`. The Makefile row asserts only `$(prog | tail -1)` against `OK` (Makefile:20130); it does not read the compiler's `ok:` line, which appears in the reports solely because twatch's diagnostic extractor picked it as the one line it found. INFERRED, NOT MEASURED: that the program printed nothing on borg — nobody on this fleet can reach borg, so the failing output has never been seen. NOT caused by the `ok:`-line change (578907347): that commit is NOT an ancestor of ad85bf019, whose report already carries the row red with the OLD spelling `code=73496B ... procs=152`. Subject is the standard Pascal old-style `object` value type with methods."
---

# Status of the evidence, separated

**Measured:**

- RED on borg in every native-tier report from `cc03b4a` (2026-09-17T16:06)
  through `e5614b0` (2026-09-18T08:39). 19 native reports in the window.
- GREEN by hand on plexus at HEAD: prints nine lines ending `OK`, rc=0.
- The assertion is `tools/expect_same.sh test_object_value_type26
  "$(... | tail -1)" "OK"` — Makefile:20130. **The compiler's `ok:` line is not
  an input to it.**
- `578907347` is not an ancestor of `ad85bf019` (`merge-base --is-ancestor`),
  and the `ad85bf019` report already lists the row red quoting the pre-change
  spelling. **The `ok:`-line change did not cause this.**

**Inferred, and by someone who could not check it:** that the program produced
no stdout on borg. The report's failure detail contains only the compile line,
which is consistent with empty program output — but the extractor quotes
whatever line it found, so this is a reading of an absence.

**NOT evidence, and it looked like evidence.** "18 reports name it on borg and
zero name it anywhere else" is vacuous: **borg is the only host producing tstate
reports at all** in that window (31 reports, all borg; 19 native, all borg). A
census over a population that cannot contain the counterexample. So "host-
specific" rests on ONE hand-run on plexus against borg's tier, not on a
comparison across hosts. Recorded because it nearly went in as corroboration.

# The one concrete difference anyone has

| | borg | plexus |
| --- | --- | --- |
| kernel | 7.0.0-29-generic | 7.0.0-31-generic |
| gcc | 13.3.0 | 15.2.0 |

`toolchain_fp: fbd303b097c6`. Whether either matters is unknown — this test is
pure Pascal and does not invoke gcc, so the gcc row is probably noise. It is
here because it is the only measured difference between the two boxes.

# First thing to do, and it is not debugging

**Get the program's actual output on borg.** Every reading so far is of a
report that does not contain it. Run the tier narrowed to this one job on borg
(the single-`--job` form the auto-filed regression tickets print) and capture
stdout — one line of output would replace this entire ticket's inference
section.

Nobody on the fleet can reach borg, which is why this has sat for a day being
re-read rather than resolved.

# Do not

Do not chase the `ok:`/`codeseg=` spelling. That was checked and excluded
above, and it is where two seats have already looked.
