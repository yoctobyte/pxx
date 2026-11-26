---
title: "crtl getaddrinfo/gethostbyname resolved no names (no /etc/hosts, no DNS) though the stub resolver was in crtl"
status: done
owner: claude-dupwt
prio: 55
area: crtl
---

busybox's hostname -d/-i and four wget tests failed on the pxx busybox:
getaddrinfo was numeric-only and gethostbyname always returned NULL.
crtl already had a stub DNS resolver (src/resolv.c, res_search) and an
answer parser (arpa/nameser.c), but nothing called them. On a pxx-built
userland, `wget http://host/` and `ping host` could not work.

__pxx_resolve4 (src/netdb.c) looks a name up in /etc/hosts first, as
glibc's `hosts: files dns' does, then sends an A query through res_search
(resolv.conf's servers and search list). It returns up to 8 addresses
and the canonical name. getaddrinfo returns one result per address
(AI_NUMERICHOST still refuses a name; the canonical name goes on the
first result). gethostbyname fills its static hostent. IPv4 only, like
the rest of the socket layer.

Differential against glibc: localhost, a hosts-only name, a numeric
address, a .invalid name and a real DNS name all give the same results.
Test row c_optzhost26 (localhost only; the suite needs no network).
