---
prio: 50
owner: claude-A
---

# FPC-compiler define profile (`fpcdefs.inc` build-config gates)

- **Type:** feature (compiler driver / per-library defines — Track A file
  ownership; consumed by Track P corpus work)
- **Status:** done
- **Opened:** 2026-07-18, out of the FPC-compiler gap analysis
- **Blocks:** [[goal-compile-fpc-compiler]] — second wall after
  [[feature-pascal-asmmode-directive-tolerance]]: every FPC compiler unit
  does `{$i fpcdefs.inc}`, whose branches are dead unless the build-time CPU
  defines are present.

## Problem

FPC's compiler is not standalone source; it is source **plus a build-config
define profile** injected by its makefile (`-dx86_64`, `-dcpu64bitalu`,
target defines, etc.). `--mimic-fpc` supplies the *language-ecosystem*
defines (`FPC`, `FPC_FULLVERSION`, `VER3_2_2`) but nothing supplies the
compiler-build profile, so `fpcdefs.inc` resolves to a nonsense
configuration and parsing dies shortly after the include.

## Fix shape

Reuse the Synapse per-library fine-grained-defines machinery: a defines
profile for "building FPC's compiler as x86-64-hosted, x86-64-target"
(`x86_64`, `cpu64bitalu`, + whatever fpcdefs.inc's include graph demands —
enumerate empirically by probing `cutils` → `cclasses` → upward). Deliver as
either a `--mimic-fpc-compiler` flag layering on `--mimic-fpc`, or a checked-
in defines file the corpus runner passes — prefer whichever the Synapse
pattern already made cheap. Document the chosen profile in the corpus dir.

## Gate

Track A driver change: `make test` + self-host byte-identical. Acceptance:
`cutils.pas` and `cclasses.pas` parse past `{$i fpcdefs.inc}` under the
profile (they may still hit later walls — those get their own tickets; see
the probe protocol in
`devdocs/progress/rainy-day/experiment-compile-fpc-as-stress-probe.md`).

---

## Resolution (2026-08-21)

`--mimic-fpc-compiler` (and `{$MIMIC FPCCOMPILER}`, its pinned-in-source
sibling): `--mimic-fpc` plus the build-config profile.

### The profile is ONE define, and that is the finding

The ticket expected a curated list, enumerated empirically by probing upward
from `cutils` → `cclasses`. The probe says otherwise: **`fpcdefs.inc` is a pure
derivation from a single build-time CPU define**, and supplies the other ~40
(`cpu64bitalu`, `cpu64bitaddr`, `x86`, `cpuextended`, `cputargethasfixedstack`,
`SUPPORT_SAFECALL`, `SUPPORT_GET_FRAME`, `cpucapabilities`, …) itself.

So the flag defines exactly `x86_64` — or `i386` / `aarch64` / `arm`, chosen
from `--target` rather than hardcoded, so a cross probe gets the right profile
without a second flag. Hand-listing the derived names was considered and
rejected: it would be a second copy of FPC's own derivation, wrong the day
upstream changes it, and wrong *silently*. The test asserts the absence of a
derived name (`derived-leak=cpu64bitalu`) to keep it that way.

### Verified against the oracle, not by proxy

The ticket's premise ("fpcdefs.inc resolves to a nonsense configuration") is
confirmed, and so is the fix, by running the same include through both
compilers:

| probe | `--mimic-fpc` | `--mimic-fpc-compiler` | `fpc -dx86_64` |
| --- | --- | --- | --- |
| cpu64bitalu | no | **YES** | YES |
| cpu64bitaddr | no | **YES** | YES |
| x86 | no | **YES** | YES |
| cpuextended | no | **YES** | YES |
| cputargethasfixedstack | no | **YES** | YES |
| USEINLINE | YES | YES | YES |
| cpawaremessages | YES | YES | YES |

**7 of 7 against the oracle.** Plain `--mimic-fpc` gets five of them wrong —
not "some walls later", but no CPU class at all, exactly as the ticket said.

One trap found by that table rather than by reading: the first version guarded
`PasApplyMimicDefines` behind `if not MimicFpc`, and since the CLI flag sets
`MimicFpc` before calling, the identity defines were skipped entirely. The
result was **worse than plain `--mimic-fpc`** — `unix` went missing, so
`cpawaremessages` died while the CPU gates came alive. Half a profile is worse
than none; the call is now unconditional (`PasDefine` skips duplicates) and the
test asserts `fpc=yes unix=yes` for exactly this reason.

### Acceptance: met

`cutils.pas` and `cclasses.pas` both parse **far** past `{$i fpcdefs.inc}`
(their line 26) and die deep inside their dependencies instead. So do
`globtype` and `cstreams`. The walls behind it are filed as their own tickets,
per the probe protocol:

- [[feature-p-fpc-global-operator-overload-declarations]] — `constexp.pas:58`,
  `operator := (const u:qword):Tconstexprint;` at unit scope. The `cutils` /
  `cstreams` path.
- [[feature-p-fpc-assigned-enum-ordinals-with-colon-equals]] —
  `globtype.pas:800`, `(ms_on := 1, ...)`. objfpc spells assigned enum ordinals
  with `:=` where Delphi uses `=`, and pxx takes only the Delphi form. The
  `cclasses` / `globtype` path. Looks like one token in one place.
- [[bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file]] — found
  *while* pinning those two down: the reported line belongs to no file
  (globtype.pas:800 reports as 1103, in an 843-line file) and the file is never
  named. Both walls above had to be located by grepping the `near:` text.

Both walls are **compiler-capability gaps**, which is the outcome the probe
protocol calls the interesting one — not RTL-surface accretion.

### Per-target results, including the two that refuse

| target | result |
| --- | --- |
| x86-64 | full profile, 7/7 vs the oracle |
| aarch64 | derives correctly (`cpu64bitalu`/`cpu64bitaddr`/`cputargethasfixedstack` yes; `x86`/`cpuextended` no — matching FPC's aarch64 branch) |
| i386 | **fpcdefs.inc's own `{$error}` fires**: *"Cross-compiling from systems without support for an 80 bit extended floating point type to i386 is not yet supported"*. pxx reproduces FPC's diagnostic faithfully, which is itself evidence the preprocessor is right. Deliberately NOT worked around by defining `FPC_HAS_TYPE_EXTENDED`: pxx's `Extended` aliases `Double`, so claiming it would bypass a guard that is telling the truth about us. |
| arm32 | hits `{$packrecords c}` in fpcdefs.inc's arm branch — filed as [[feature-p-packrecords-c-directive]] |
| riscv32, xtensa | **refused with a clear message.** FPC 3.2.2's fpcdefs.inc has no branch for either, so any define invented here would select nothing and hand back the same no-CPU-class configuration the flag exists to fix. |

### Test

`test/test_mimic_fpc_compiler_profile.pas`, repo-local (needs no FPC tree), on
x86-64 and aarch64. Four assertions: no flag defines nothing; `--mimic-fpc`
does NOT define the CPU; `--mimic-fpc-compiler` carries the identity AND the
CPU; and no derived name leaks.

### Gate

`make compiler/pascal26` (byte-identical fixedpoint) + the oracle table above +
`tools/gate.sh quick`. Cross-target breadth is Track T's, against this sha.

## Log
- 2026-08-21 — resolved, commit bda942a0b.
