---
track: A
prio: 90
type: bug
status: done
found: 2026-09-28
found-by: frankd-90
owner:
summary: "DATA LOSS. `pxx g.pas ./g.pas`, `pxx g.pas /abs/g.pas`, `pxx g.pas a/../g.pas` and an output that is a symlink to the source write the ELF over the source file: the driver's guard compared spellings (`outFile = inFile`) and renamed only the byte-identical one to `.out`. The same holds for a unit or a C header the compile reads. v445 (caf21ac399f1) clobbers all of them."
---

# The output can overwrite the source under another spelling

```sh
pxx g.pas ./g.pas      # exit 0, g.pas is now an ELF
```

## Resolution (2026-09-28)

Compared by IDENTITY: compiler/output_guard.inc reads `mnt_id` and `ino` from
/proc/self/fdinfo of an O_PATH descriptor (there is no stat intrinsic; the
compiler already reads /proc through sysopen/sysread). The driver records the
output's identity once, when the output already exists, and refuses when the
source is it. Every other input read goes through `LoadInput` (LoadFile plus
the check): Pascal units and includes, C sources and headers, objects and
libraries read for linking, resources. LoadFile itself is an intrinsic in a
self-hosted compiler, so the check cannot live in its body.

A NAMED output with the source's exact spelling is now refused as well (it
was renamed to `<source>.out`); a DEFAULTED output equal to the source (`pxx
g`, no extension) keeps the `.out` rename. Without /proc the spelling check
remains, as before.

Not covered: elfdynsym.inc's .dynsym probe of a candidate shared library
(test_elfdynsym.pas includes that file standalone, without the guard), and
side artefacts beside the output (a map file) -- neither is a named output.

Fixed with it: `--no-lazy-var`'s error told the user to pass `--lazy-var`,
an unknown option; it now names the option that disabled the feature.

Fixture `test/the_output_may_not_be_an_input.sh` (13 rows; test-core): v445
fails 11, this build none. Cost measured on the self-host compile with an
existing output: 204 extra opens, no measurable time.
