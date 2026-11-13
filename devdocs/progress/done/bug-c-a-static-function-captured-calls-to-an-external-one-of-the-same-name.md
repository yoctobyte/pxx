---
track: C
tags: [c, linkage, static, crtl, miscompile, dropbear]
prio: 80
type: bug
blocked-by: []
summary: "A file-scope `static` function in one C module and a function with external linkage of the same name in another shared one Procs row, and the static body won. Calls from a third module, and `&name`, reached the static. crtl's crypt.c `static void sha512_init(sha512_ctx *)` captured dropbear's calls to libtomcrypt's `int sha512_init(hash_state *)` in every file that included <crypt.h>: the hash state was written 8 bytes off, ed25519 signatures were garbage, and OpenSSH refused every login. The two are now two rows, in either declaration order."
status: done
owner: claude
---

# A static function captured calls to an external one of the same name

Found running the pxx-built dropbear 2026.94
([[feature-c-dropbear-builds-with-pxx]]). Every login using an ed25519 key
failed with `incorrect signature`.

**Cause.** pxx compiles a C program as one buffer in which every include,
including the crtl sources a header pulls in, is a module. C 6.2.2 gives a
file-scope `static` internal linkage. RUNG S (ParseCSubroutine) already
split two same-named statics in different modules
([[feature-c-two-same-named-file-scope-statics-share-one-procs-row]]). Its
comment noted that a static meeting an external function of the same name
"no corpus produces". dropbear does:

- crtl's `crypt.c` (added for dropbear the same day) has private SHA helpers
  named `sha256_init`, `sha512_init`, and so on.
- libtomcrypt exports `sha512_init(hash_state *)`.
- dropbear's `includes.h` includes `<crypt.h>`, so each such file's buffer
  contained both.

The static definition took the prototype's row, so `curve25519.c`'s
`sha512_init(&hs)` ran crtl's helper on a `hash_state`. Isolated with a
differential harness: SHA-512 was correct in a TU without `includes.h` and
wrong with it. The disassembly showed the call bound to a local symbol.

A two-module repro also showed the address side. In one order, `&tag` from
the private module returned the *public* function.

**Fix (compiler/cparser.inc).**

- **RUNG X in ParseCSubroutine.** A `static` declaration reaching a C row with
  external linkage gets its own row. A non-static declaration reaching
  another module's static row takes the external row, or a new one. gcc
  rejects the mixed pair inside one real TU ("static declaration follows
  non-static"), so in one buffer it can only mean two modules. Pascal rows
  are not touched.
- **Static prototypes.** A `static` prototype now records its internal
  linkage and its module when it is declared, not only at the definition.
  Without that, the forward `static ... sp_parse(...);` in crtl's `time.c`
  and the static `sp_parse` in `shadow.c` split into a bodyless row ("unresolved
  forward"). The module walks accept a static row of the asking module whether
  or not its body has been seen yet.
- **CFindProcFromModule.** When the first-registered row is another module's
  static, the caller gets its own module's static if it has one, else the
  external row (`CFindExternalProcRow`).

**Test.** `test/c_static_vs_external_same_name.c` with
`test/fixtures/cstatic_ext_priv.c` and `cstatic_ext_pub.c`:

- Rows `cstaticext26` and `cstaticext26b` run both declaration orders. They
  check calls and addresses from both sides against gcc's separate-TU build,
  `10 1005 1007 14 10` (pxx printed `1005 1005 14 14 -1` before the fix).
- Row `cstaticext26.o` checks that `--emit-obj` writes one LOCAL and one
  GLOBAL `tag`, as gcc does.

The existing `cstatic_two_modules_distinct` rows are unchanged.

**Follow-up worth doing.** crtl has many unprefixed private helpers (`fill`,
`widen`, `h_init`, `sha256_block`, ...). They are correct now, but a
`__crtl_` prefix on new ones costs nothing.
