# A dotfile's name was treated as its extension — ChangeFileExt ate the filename

- **Type:** bug — Track B (library), tag `compat` (FPC parity)
- **Status:** done
- **Resolved:** 2026-08-04 in `622a8a055` (verified on origin/master after the rebase)
- **Opened:** 2026-08-04
- **Found by:** `tools/fpc_diff_probe.sh`, new `su-extractext` case.

## Symptom

A dot that is the **first character of the basename** starts a hidden file; it
does not introduce an extension. Both path helpers scanned down to `sep + 1`
and so counted it:

| call | FPC | pxx (before) |
| --- | --- | --- |
| `ExtractFileExt('.hidden')` | `` | `.hidden` |
| `ExtractFileExt('/a/.hidden')` | `` | `.hidden` |
| `ChangeFileExt('.hidden', '.bak')` | `.hidden.bak` | **`.bak`** |
| `ChangeFileExt('/a/.hidden', '.bak')` | `/a/.hidden.bak` | **`/a/.bak`** |

The unaffected cases (`/a/b.c.txt`, `noext`, `/x.y/name`, `trailing.`) all
already agreed, which is why one wrong constant looked right.

## Severity — the second row is the real one

`ExtractFileExt` returning a wrong string is a wrong value. `ChangeFileExt`
**truncating at the leading dot destroys the filename**: `.bashrc` becomes
`.bak`. Anything doing the standard "write to a temp name, then rename"
or "make a backup copy" dance on a dotfile would have written to, or clobbered,
a path it never meant to touch. Silent, plausible, and destructive — no error
anywhere.

## Root cause

One character, in two places: the backward scan bound was `sep + 1` (the first
character of the basename) instead of `sep + 2`. `sep` is `LastPathSep`, so
`sep + 1` is exactly the leading-dot position that must be excluded.

## Fix

`lib/rtl/sysutils.pas` — `sep + 2` in both `ExtractFileExt` and
`ChangeFileExt`, with the rule stated at each.

## Test

`test/lib_paths.pas`, 14 -> 20 assertions. **It had no dotfile case at all** —
that gap is precisely why both functions could carry the same wrong bound. Now
covers the plain dotfile, one in a directory, a dotfile that genuinely has an
extension (`/a/.hidden.txt` -> `.txt`), the trailing-dot case (FPC returns
`.`), and both destructive `ChangeFileExt` forms. The file compiles under FPC
and the rows were read off an FPC build. 4 fail without the fix.
