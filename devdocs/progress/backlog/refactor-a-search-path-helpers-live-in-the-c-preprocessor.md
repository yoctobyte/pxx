---
track: A
prio: 25
type: refactor
blocked-by: []
summary: "AddPasUnitDir / AddPasIncDir / AddCIncludeDir are generic search-path functions that live in cpreproc.inc, so compiler.pas's own -Fu/-I handling depends on the C frontend. Six of the eleven errors from omitting the C frontend are this misplacement, not coupling: moving them drops omit-c from 11 sites to about 4."
---

# Search-path helpers live inside the C preprocessor

Found 2026-08-19 while measuring
[[feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets]] by omission.

Omitting the C frontend (`clexer.inc`, `cparser.inc`, `cpreproc.inc`) gives 11 errors. **Six
are `AddPasUnitDir` and one is `AddPasIncDir`** — called from `compiler.pas`'s ordinary
command-line handling for `-Fu` and `-I`, which have nothing to do with C:

    compiler.pas(723,7)  AddPasUnitDir      compiler.pas(729,7)  AddPasIncDir
    compiler.pas(736,7)  AddCIncludeDir     compiler.pas(737,7)  AddPasUnitDir
    compiler.pas(906,7)  AddPasUnitDir      compiler.pas(913,7)  AddPasUnitDir
    compiler.pas(915,5)  AddPasUnitDir

The name says it: `AddPas...` in `cpreproc.inc`. It is a **misplacement, not coupling** —
nothing about a Pascal unit search path belongs to the C preprocessor, and the only reason it
sits there is that the C include-path code needed a list first.

## Fix

Move the three `Add*Dir` helpers (and whatever state they own) to a shared file — `defs.inc`
or a small search-path section in `parser.inc`. No behaviour change; `omit-c` drops from 11
sites to about 4, and the remaining four are the real ones (`CLexAppend`, `CLexAll`,
`ParseCProgram`, and one in `parser.inc`).

Worth doing independently of the reduction feature: today a reader looking for how `-Fu` is
handled has no reason to open the C preprocessor.

## Gate

Track A's: `make compiler/pascal26` (byte-identical fixedpoint) + `tools/gate.sh quick`.
