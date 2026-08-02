---
track: P
prio: 25
type: bug
---

# `unit X deprecated 'msg';` — a unit hint directive is a parse error

- **Type:** compat (Pascal frontend, reference parity with FPC/Delphi) —
  **Track P**. Slug follows the `compat-<lang>-*` convention.
- **Found:** 2026-08-02, incidentally, while reaching Synapse's SSL units.

## Measured

`external/synapse/ssl_openssl.pas:2320` ends with the perfectly ordinary

```pascal
unit ssl_openssl deprecated 'Use ssl_openssl3 with OpenSSL 3.0 instead';
```

and pxx stops on it:

```
pascal26:2320: error: unexpected token
  near: end  end  unit ssl_openssl >>> deprecated Use ssl_openssl3 with OpenSSL 3.0 instead
```

FPC and Delphi both accept hint directives on a unit declaration —
`deprecated` (with or without a message string), `platform`, `experimental`,
`library`, `unimplemented`. They are advisory: the unit still compiles, the
compiler may emit a warning at the use site.

## Impact — real but bounded

It is a hard parse error, so a unit carrying the directive cannot be compiled
at all, and a *deprecated* unit is exactly the kind a real-world codebase keeps
around for compatibility. It cost nothing here because `ssl_openssl3` is the
one to use on this box anyway; it would cost a lot on a project pinned to the
older unit.

Not a silent-wrong-behaviour bug — it fails loudly and immediately, which is
why this is `compat` rather than a `bug-` escalation.

## Fix shape

Accept and ignore (or warn on) the hint-directive suffix on a unit
declaration, and on the other declarations that take them (procedures, types,
variables, class members) if those are not already handled — worth checking in
the same pass rather than fixing one spelling.

## Gate

`unit X deprecated 'msg';`, `unit X deprecated;`, `unit X platform;` and
`unit X experimental;` all compile; a program using the unit still builds and
runs. `external/synapse/ssl_openssl.pas` reaching the same wall the
OpenSSL-3 unit does rather than a parse error is the real-world check.
