# Relative/absolute path support in `uses`/`includes`

- **Type:** feature
- **Status:** working
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
