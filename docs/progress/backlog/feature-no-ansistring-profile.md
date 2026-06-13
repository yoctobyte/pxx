# No-AnsiString / bounded-string profile

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-13 (from user note after arm32 SysOpen family)

## Motivation

Managed `AnsiString` is the practical default for the compiler and hosted
targets, but embedded targets such as ESP32 may want a profile that avoids
managed strings, heap traffic, and large implicit buffers.

The current frozen/non-`AnsiString` path historically used very large fixed
buffers per string. That is the wrong default for small programs and embedded
output paths: traditional Pascal short strings cap at 255 bytes, while truly
large buffers should be explicit (`array of Byte`, a deliberately large fixed
string/buffer type, or another chosen storage shape).

This is not a blocker for the managed cross path. It is a separate profile and
dialect/runtime policy decision.

## Scope

- Define the intended no-managed-string profile:
  - default bounded string size suitable for small embedded programs;
  - explicit opt-in for larger fixed buffers;
  - guidance for byte buffers versus text strings.
- Audit compiler/runtime code that assumes `AnsiString` availability and mark
  the minimum conditional seams needed for a maintainable no-`AnsiString` build.
- Keep the policy compatible with Pascal expectations: short bounded strings by
  default, explicit capacity when larger storage is needed.
- Add tests for small-output cases such as hello-world style writes without
  pulling in managed string support.
- Decide whether this belongs as:
  - a compiler define/profile;
  - a dialect mode;
  - or a target policy selected by embedded targets.

## Acceptance

- A documented no-`AnsiString` profile exists and can compile/run at least a
  small embedded-oriented Pascal program without large per-string BSS buffers.
- The compiler errors clearly when a program needs managed-string-only behavior
  under this profile.
- Existing managed `AnsiString` behavior remains unchanged.

## Log

- 2026-06-13 — ticket opened. Keep arm32 `SysOpen` managed-path-only for now;
  revisit frozen/string-buffer support as part of this profile instead of
  broadening every syscall path ad hoc.
