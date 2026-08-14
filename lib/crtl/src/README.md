# crtl implementations

The bodies behind `lib/crtl/include`. Seventeen files covering the parts of the
C runtime the corpora and tests actually exercise — `stdio`, `stdlib`, `string`,
`math`, `time`, `signal`, `setjmp`, `pthread`, `wchar`, `ctype`, `locale`,
`unistd`, `fcntl`, `poll`, `inttypes`, `assert`, plus the `sys/` and `netinet/`
groups.

Each file is pulled automatically when its sibling header resolves, at most once
per compile — see `../README.md` and
`devdocs/dev/c-linking-and-crtl-autopull.md`.

## House rules

- **Project-owned, libc-free.** Do not copy host libc sources into this tree.
- **Reach the machine through the PAL, not through a syscall.** Anything the
  operating system provides goes via the `__pxx_*` entry points, which are the
  shared, prefixed layer every frontend uses.
- **Do not delegate C semantics to the Pascal RTL.** It was tried and it broke C
  programs silently for months; see below.

## math.c is the big one, and it is deliberately its own

~114 functions on correctly-rounded double-double kernels, **not**
glibc-bit-compatible: where glibc is not correctly rounded, crtl stays correctly
rounded (`decide-crtl-libm-glibc-bit-parity`). State that as *"correctly
rounded, judged against high-precision references"*, never as a glibc match.

It is a peer of `lib/rtl/math.pas`, not a wrapper around it. The two disagree on
purpose — `round(2.5)` is 3 in C and `Round(2.5)` is 2 in Pascal, both correct —
and an earlier attempt to have C borrow Pascal's math made `pow(2,10)` return 1
with nothing to see at either call site. **`devdocs/dev/math-implemented-twice.md`**
has the measurements and the rule.

Ten functions here are still named `__crtl_exp`, `__crtl_sin`, … to dodge a
case-insensitive collision with Pascal's `Exp`/`Sin` that no longer fires;
retiring those prefixes is `task-c-retire-the-crtl-name-dodge-prefixes`.
