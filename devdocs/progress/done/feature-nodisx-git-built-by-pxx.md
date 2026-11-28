---
summary: "Nodisx: git 2.56.1 (with git-remote-http on libcurl/mbedTLS, zlib) built on site by pxx alone; matches gcc's git on 12 rows"
type: feature
prio: 50
tags: [nodisx]
---

# Nodisx: git built by pxx

- **Type:** feature (Nodisx recipe). Assigned 2026-11-27 by pixx-cc: a git
  recipe in tools/nodisx, built by pxx like curl.
- **Status:** done (2026-11-28)

## What landed

tools/nodisx/git/ has record.sh, onsite.sh, test.sh and scenario.sh. The
README has a git section. In onsite-all.sh git comes after curl.
- git 2.56.1, zlib 1.4, and libcurl 8.23.0 on mbedTLS 3.6.8. libcurl is
  configured with curl's recipe arguments, now in curl/configure.args and
  shared by both recipes. The two new tarballs are pinned in sources.lock.
- 762 units. git links 441 objects and git-remote-http 481; the https,
  ftp and ftps helpers are copies of git-remote-http. The templates are
  installed too.
- test.sh compares pxx's git with gcc's on 12 rows:
  - version, history, branches, worktree, objects, sha256 and clone-file;
  - clones over http, https-ec and https-rsa;
  - an https clone with the wrong CA, which both refuse.
  The result is `git recipe: PASS`.

## Found and fixed on the way

- bug-c-a-comma-or-assignment-in-a-constant-expression-arm-is-not-read
  (git's MOVE_ARRAY / BARF_UNLESS_COPYABLE)
- bug-c-sizeof-of-a-vla-without-parentheses-is-the-pointer-size (a silent
  miscompile)
- bug-crtl-unistd-h-declares-getopts-struct-option (git's own struct option)
- bug-c-a-parenthesised-function-parameter-declarator-is-not-read (glibc
  regcomp.c, git's compat/regex)
- feature-crtl-sync-file-range (git's wrapper.c)
- Recipe tools:
  - units-from-make.sh reads `rm -f X && ar`, `/usr/bin/ar`,
    single-quoted flags and quoted words holding spaces.
  - Every onsite.sh marks a unit whose eval fails on quoting; it used to
    show only at link.
  - glibc-elided fallbacks (compat/obstack.c) are linked.

Opened as backlog:
- bug-c-a-struct-redefinition-in-one-scope-is-silently-ignored
- bug-c-crtl-sources-share-their-header-tags-with-the-program

## Limits

- Git 3.0 will require Rust. Neither pxx nor gcc compiles Rust, so a git
  3.x recipe needs rustc on the build host and a Rust story for the target.
  NO_RUST works through 2.x.
- Not yet run in the Rainyday guest (test-onsite-rainyday.sh).
- No perl, python, Tcl/Tk, gettext or expat, so no git-svn, gitk, git-gui,
  http-push or translations.
- Dumb HTTP only in the test. There is no smart-HTTP server here; the
  client side is the same libcurl.
