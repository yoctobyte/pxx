
- 2026-07-08 (fable-c, C ladder / slice B) — imported stb, cglm, ENet
  (installer fetchers `stb`/`cglm`/`enet`, pinned commits, gitignored). First
  probes under `test/gamelib/`, each mapping a first compiler/runtime gap:
  - **stb** (stb_sprintf.h) → inline fn-pointer PARAM call not registered:
    [[bug-c-inline-fnptr-param-call]].
  - **cglm** → (1) crtl lacked the C99 float-math family (added fabsf/sqrtf/...
    then REVERTED on discovering (2)) float-returning C functions return 0:
    [[bug-c-float-single-return-zero]]; and local nested aggregate initializers
    fail: [[bug-c-local-nested-aggregate-init]].
  - **ENet** → crtl missing `<netinet/tcp.h>`/`<netdb.h>`/`<poll.h>`
    ([[bug-c-crtl-missing-net-headers-enet]]) → host-header fallback redefines
    `struct in_addr` and trips a struct-tag-redefinition field-misfile that
    makes a record self-referential → compiler SIGSEGV
    ([[bug-c-tag-redef-misfiles-field-selfref-segv]]).
  Landed in-lane and green: crtl `arpa/inet.h` IPv4 text conversion
  (inet_aton/inet_addr/inet_pton/inet_ntop — ENet's actual needs, all
  pointer-based) + `test/gamelib/crtl_inet_smoke.c` in test-core. inet_ntoa
  (4-byte struct BY VALUE) omitted — hits a small-struct-byval param gap, not
  needed by ENet. Slice B acceptance (each candidate: passing probe OR filed
  gap) met for the three C candidates. Pascal ladder (slice C) unstarted —
  Track B.
