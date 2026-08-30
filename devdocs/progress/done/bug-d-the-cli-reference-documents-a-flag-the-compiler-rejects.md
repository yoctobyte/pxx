---
track: D
prio: 40
type: bug
blocked-by: []
summary: "docs/reference/cli.md listed `--selftest` as a compiler option. It is not one and never was: the name belongs to the lib_chess demo and to tools/release.sh. A reader following the CLI reference got `unknown option`. One row, removed. The sweep behind it also produced the category split bug-a-help-does-not-advertise-flags-the-compiler-accepts needs."
status: done
owner: frankD
---

# The CLI reference documented `--selftest`, which the compiler rejects

- **Type:** bug — **Track D** (`docs/**` only). Spun out of
  [[bug-a-help-does-not-advertise-flags-the-compiler-accepts]] [A p35]; that
  ticket keeps the compiler-side half.
- **Found 2026-08-30 by frankD**, sweeping `docs/**` for flags the compiler does
  not accept. Measured against `$(PXX_STABLE)`; no rebuild.

## The defect

`docs/reference/cli.md:228`, in the *"Diagnostics and internal flags"* table:

| Option | Effect |
| --- | --- |
| `--selftest` | Run the built-in self-test. |

```
$ pascal26 --selftest t.pas
unknown option: --selftest
```

Five spellings tried — `--selftest`, `--self-test`, `-selftest`, `--self_test`,
`--selftest=1` — all rejected. **This is the strict form of a documentation bug:
the reader does exactly what the page says and it fails**, on the one page whose
whole job is to answer "what flags are there".

## Where the row came from, which is the interesting part

`--selftest` is real — it just belongs to two other programs:

- `lib_chess --selftest`, the chess demo, asserted at `Makefile:16358`;
- `tools/release.sh --selftest`, its version-bump unit tests.

It also appears twice inside `compiler/**`, and **both are comments** —
`ir_codegen_riscv32.inc:2091` and `ir_codegen_xtensa.inc:2072` quote
`ParamStr(1) = '--selftest'` as a frozen-string equality example. So a search of
the compiler tree for `selftest` returns two hits in compiler source, and neither
is an option. **A flag named in a compiler comment is indistinguishable from a
flag the compiler accepts, to anyone reading rather than running.**

## Fixed

Row removed. No replacement text: a CLI reference should not carry an erratum for
an option that never existed, and the reasoning belongs here.

**The seven surviving rows in that table were each run before the edit landed** —
`--dump-cpp`, `--proc-map`, `--measure-inline`, `--measure-regcall`,
`--warn-missed-fold`, `--warn-self-result`, `--warn-uses-leak` — all accepted,
three of them producing visible output. The neighbours were verified rather than
assumed, because a bad row's neighbours are the next most likely to be bad.

## The aperture, in the sentence rather than below it

**This sweep checked which flags EXIST, not what they apply to.** A page that names a
real flag and lies about its targets or its accepted sources passes every check here,
because the flag is in both lists. One such claim was found the same day and it was on
this very page — `--emit-obj` "on any target", false on three of six backends. See
[[bug-d-docs-scope-claims-about-a-flag-are-invisible-to-a-flag-existence-sweep]].
**Do not read the result below as "the docs agree with the compiler".**

## The rest of the page's flag EXISTENCE is right — 62 of 63

Every flag presented in a `docs/reference/cli.md` table was run. **Exactly one
was rejected.** Two more looked rejected and were my probe's fault, not the
page's: `--target=ARCH` and `--xtensa-abi=call0\|windowed` are a metavariable and
a doc alternation, and both work with real values.

## The trap this sweep sets, recorded because I walked into it

**A bad VALUE for a known option is reported as `unknown option`.** Measured:

| | |
| --- | --- |
| `--target=x86_64` | ok |
| `--target=x` | `unknown option: --target=x` |
| `--xtensa-cpu=lx6` | ok |
| `--xtensa-cpu=esp32` | `unknown option: --xtensa-cpu=esp32` |
| `--esp-profile=bare` | accepted (then complains about the *target*) |
| `--esp-profile=idf` | `unknown option: --esp-profile=idf` |

So a probe that supplies a placeholder value calls a working option nonexistent.
**I nearly filed `--xtensa-cpu=lx6` — which is documented correctly — as a second
category-2 hit**, and only caught it by trying the value the page actually names.
Filed for the owning lane as
[[bug-a-a-bad-value-for-a-known-option-is-reported-as-an-unknown-option]].

## What the search could not have seen

An absence claim needs its blind spots stated:

- the candidate generator was `--[a-z][a-z0-9-]+` over `docs/**`, so it cannot
  see a **short-form** flag (`-Fu`, `-O2`, `-d<define>`) or a flag written with an
  interior capital;
- it cannot see a flag named only in **prose without the leading dashes**;
- it read `docs/**` only — `devdocs/**` and `README.md` were out of scope.

`--fu` and `--warn-` in the raw candidate list were both artefacts of that regex
(`-FuDIR` and a prose `--warn-*`), and `--static` was matched inside a sentence
saying pxx has **no** such flag. Mention is not use; three of thirteen candidates
died on that distinction.

## Not defects — other programs' flags, correctly documented

`--chip` (`tools/esp_run_bare.sh`), `--yes` / `--uninstall` / `--bindir`
(`install.sh`). The page is right; they are simply not pxx's.

## Gate

`docs/**` internally consistent; every flag in the edited table run against
`$(PXX_STABLE)`. Compiler not rebuilt.

## Log
- 2026-08-30 — resolved, commit ba5deef98.
