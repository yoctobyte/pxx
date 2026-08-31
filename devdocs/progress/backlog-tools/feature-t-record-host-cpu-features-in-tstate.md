---
track: T
prio: 20
type: feature
blocked-by: []
summary: "tstate records host, sha, tier, wall and compiler_sha256 — nothing about the machine. So 'can we emit FMA?' could not be answered from the repo and needed an ssh into plexus. Record CPU model and the x86-64 feature level per host, once, in the host json."
---

# tstate: record each host's CPU model and feature level

- **Type:** feature — **Track T** (`tools/twatch.py`, `devdocs/progress/tstate/**`).
- Prompted 2026-08-15 by [[feature-opt-arch-level-and-dispatch]]: deciding
  whether pxx may emit FMA needs to know what the gate boxes actually are, and
  the answer was not in the repo.

## What is missing

`devdocs/progress/tstate/plexus.json` and the report frontmatter carry `host`,
`sha`, `tier`, `wall`, `verdict`, `compiler_sha256`. Nothing identifies the
machine beyond its name. So an ISA question — the kind that decides whether
generated code runs at all — cannot be answered without logging in.

Measured by hand this time:

| host | CPU | level |
| --- | --- | --- |
| plexus | Xeon E5-2620 v2, Ivy Bridge EP 2013, 12 cores | **v2** (avx yes, avx2 no, **fma no**) |
| borg | *unknown* | *unknown* |
| dev box | i7-6700 Skylake | v3 |

## The work

Write it once per host into the existing `<host>.json`, alongside whatever
identifies the run — model string, core count, and a derived
`x86_64_level: 1|2|3|4` plus the raw flags that decide it (`sse4_2`, `avx`,
`avx2`, `fma`). It changes only when the hardware does, so it is a startup
probe, not per-run data.

Worth including for the non-x86 runners too when they exist (aarch64 needs no
FMA gate — `FMADD` is baseline — but core count and model still explain a wall
time).

## Why it earns its keep beyond the ISA question

Bench rows are already compared across hosts (`bench.tsv` carries a `host`
column and a scale factor). A 2.1 GHz Ivy Bridge and a 3.4 GHz Skylake are not
the same measuring stick, and right now nothing in the file says so.

## Gate

Track T's own tooling gate, green, and the field present in a freshly published
report.

## Second consumer, 2026-08-31: the rdrand skip hole (16 days after filing)

This ticket was filed 2026-08-15 for an **ISA** question — may pxx emit FMA —
and its summary still describes only that. A second, unrelated consumer arrived
sixteen days later by a different route and is worth recording, because neither
looks like the other held alone:

**seven's full-tier runs carry a permanently unrunnable rdrand job**
(`skip_holes` 1 in 120 of 121 full runs, 2 in the other; never 0). The harness
asserts that job is structurally unrunnable on that box, and **that assertion
cannot be verified from the repo** — `seven.json` carries no hardware fields at
all, and every session on this machine is on **plexus**, which *does* have
rdrand. So nobody here can check the claim about seven either way, which is
exactly the gap this ticket describes.

The consequence is filed separately as
`decide-the-proof-grade-gate-is-unsatisfiable-on-the-host-that-does-the-sweeping`:
the `-O3` promotion gate requires `skip_holes == 0`, which seven can never
produce, and the enumerated-allowlist option recommended there **needs this
ticket's field to exist** — an allowlist entry has to name the hardware reason,
and today there is nowhere to read it from.

**Two consumers, one missing field.** Worth a prio look — 20 was set when this
had one ISA-shaped consumer. Left unchanged here: it is frankT's ticket and the
ranking call is the owner's.

Recorded by the Track U session from a frankT finding relayed by
frank-coordinator, both of which deliberately did not edit it.
