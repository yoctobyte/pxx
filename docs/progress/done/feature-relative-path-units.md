# Relative/absolute path support in `uses`/`includes`

- **Type:** feature
- **Status:** done
- **Owner:** claude
- **Opened:** 2026-06-07 (manual request)

## Problem

The unit resolver currently only handles unit names (identifier-based lookup).
It does not support relative paths (`uses '../lib/foo'`) or absolute paths in
`uses` or `{$include}` directives.

## Desired Behaviour

- `uses './subdir/myunit'` or `uses '../shared/util'` should resolve relative
  to the file containing the directive.
- Absolute paths (`uses '/opt/libs/thing'`) should work as-is.
- Extension may be omitted (compiler infers `.pas`).
- Existing identifier-based resolution continues to work unchanged.

## Scope

- Extend the unit/include resolver to accept path separators.
- Normalise paths (collapse `..`, handle trailing slash edge cases).
- Emit clear error when a path-based reference cannot be found.

## Acceptance

A test program using a relative-path `uses` compiles and links correctly.

## Log

- 2026-06-07 — ticket opened from user note.
- 2026-06-10 — delivered. Path-form `uses './sub/unit'` (quoted string in the
  uses list) resolves relative to the directive's file via the new `CurUnitDir`
  global (saved/restored per nested unit parse); absolute paths as-is;
  `NormalizePath` collapses `.`/`..`; extension inferred (`.pas` then `.pp`) or
  explicit `.pas`/`.pp`/`.c`/`.h`; miss errors with the resolved path (the
  identifier-form error now names the unit too). `{$include}` accepts absolute
  paths. Dedup key remains the lowercased basename, so path-form and
  identifier-form of the same unit dedup together. Test:
  `test/test_relpath_uses.pas` + `test/relpath/` (in `make test`); bootstrap
  fixedpoint, `make test`, `make test-nilpy` all green.
- 2026-06-10 — commit 4aa293a (feature), 8896955 (LoadFile debug-writeln cleanup found en route).
