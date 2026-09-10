---
slug: decide-c-should-a-libc-symbol-from-an-unresolvable-header-bind-to-libc
track: U
type: decide
prio: 40
status: backlog
owner: ""
created: 2026-09-10
found-by: frankH
tags: [cfront, headers, elf, dt-needed]
blocked-by: []
summary: "`import \"/usr/include/strings.h\"` + a call to `ffs` is REFUSED: the compiler invents `libstrings.so`, no library answers to it, and the build stops. `ffs` is in libc.so.6 and the compiler can see that it is — CSynthDirAnswersFor already asks libc's own .dynsym — but that arm is deliberately scoped to a header whose DIRECTORY named a real library, so a top-level /usr/include header never reaches it. The fork is whether that scope is right: bind to libc when libc demonstrably exports the symbol, or keep refusing so a name collision cannot bind silently. Nothing is blocked on this today."
---

# What happens now

```
printf 'import "/usr/include/strings.h"\nprint(ffs(8))\n' > /tmp/pc.npy
./compiler/pascal26 /tmp/pc.npy /tmp/pc
pascal26:1: error: this build would die at exec: `ffs` is imported from
libstrings.so, which no library on this machine answers to. ...
```

`ffs` is in libc.so.6. `strings.h` sits directly in `/usr/include`, so
`CSynthDirName` is `include`, `LdCacheDirCandidate` finds no `libinclude.so`,
state goes to 2, and `CSynthDirAnswersFor` exits before its libc/libm arms —
the arms that would have answered correctly.

Under `SDL2/SDL_version.h` the same symbols DO resolve, because that directory
names an installed library and the state-1 gate opens. So the outcome depends
on a property of the header's directory that has nothing to do with where the
symbol lives.

# The scope is deliberate, and its argument is in the code

`pasparser_proc.inc`, `CSynthDirAnswersFor`:

> SCOPED to a header whose directory DID name a real library (state 1).
> Without that, a header naming no library at all keeps today's error, which is
> the right answer for it — this is not a general licence to satisfy any
> unresolved symbol out of libc.

That is a real hazard and not a hypothetical: a header declaring its own `open`
or `index` wrapper would bind to libc's under the wider rule, silently, where
today it errors loudly.

# The fork, stated as what we want

**Do we want an import whose library we cannot name to fail loudly, or to
succeed whenever the symbol demonstrably comes from libc?**

The evidence standard is the same either way — libc's own `.dynsym` is read,
not guessed. What changes is which mistake we prefer to make: refusing a build
that would have worked, or linking a same-named-but-different function.

Note the wider rule is not "satisfy anything out of libc": a header
synthesising `libfoo.so` and declaring `foo_init` still errors, because libc
does not export it. Only names libc actually defines are absorbed.

# Not urgent

The one fixture that hit this (`test_nilpy_qualified_name_error_names_the_
receiver`) was moved off `strings` in `0997c6088` for an unrelated and correct
reason, so no row is red on it. Found while landing
`bug-c-an-unresolvable-synthesised-soname-still-reaches-dt-needed`, whose fix
does not touch this scope.
