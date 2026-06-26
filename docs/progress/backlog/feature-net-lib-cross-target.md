# net lib cross-target build matrix — i386 + arm32 backend gaps

- **Type:** feature (Track A — i386 / arm32 codegen)
- **Track:** A — `compiler/**`
- **Status:** backlog (filed by Track B)
- **Owner:** — (Track A)
- **Opened:** 2026-06-25
- **Found-by:** [[feature-own-net-http-lib]] — cross-compiling
  `examples/net/httpdemo.pas` (the net showcase: `http` + `scheduler` +
  `asyncnet` + `dns` + `tls` + `zlib` + `base64`) across the four cross targets.

## What works

Building `pxx -Fulib/rtl/platform/posix examples/net/httpdemo.pas` against the
pinned stable:

| Target   | Result |
| -------- | ------ |
| amd64    | ✓ builds + runs (primary; `net-demo` smoke) |
| aarch64  | ✓ builds clean |
| i386     | ✗ backend gap (below) |
| arm32    | ✗ backend gap (below) |

So the net library source is portable; the two failures are general backend
limitations the net stack happens to exercise, not net-lib bugs.

## i386

```
pascal26:611: error: target i386: only ordinal/pointer parameters supported yet ()
```

The i386 backend (early-stage, "grows with the backend" per the Makefile) does
not yet pass non-ordinal/pointer parameters by value — i.e. record/aggregate or
real-typed value params. The net lib passes records (`THttpRequest`,
`THttpConnection`, `TInetSockAddr`, …) and `AnsiString` by value/const widely.

## arm32

```
pascal26:146: error: target arm32: virtual call with more than 4 parameter words not supported ()
```

A virtual call somewhere in the dependency graph (likely the TLS seam / widget-ish
indirection, or a method taking several wide params) exceeds the 4-param-word
limit the arm32 backend currently allows for virtual dispatch. Sibling of
[[feature-arm32-large-aggregate-result]] — same AAPCS-wide-args theme, dispatch
side. Pinning the exact call needs an arm32-side bisect (Track A).

## Done when

`httpdemo` (and `make lib-test`'s `net-demo`) cross-compiles on i386 and arm32 in
addition to amd64 + aarch64. Track A owns the backend changes; Track B will add a
cross smoke once the backends accept it.
