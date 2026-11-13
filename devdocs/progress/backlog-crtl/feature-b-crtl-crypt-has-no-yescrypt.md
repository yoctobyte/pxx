---
track: B
tags: [c, crtl, dropbear]
prio: 30
type: feature
blocked-by: []
summary: "crtl's crypt() does SHA-crypt ($5$/$6$) only. yescrypt ($y$), the default for new passwords on current Debian/Ubuntu, and bcrypt/MD5-crypt answer NULL/EINVAL. So a pxx-built dropbear cannot check such a password, and password login fails for those accounts. Public-key login is unaffected."
status: open
owner: unassigned
---

# crtl crypt() has no yescrypt

lib/crtl/src/crypt.c implements Drepper's SHA-crypt, which is what Alpine
(musl) and older glibc systems store. On plexus `/etc/login.defs` says
`ENCRYPT_METHOD YESCRYPT`, so any password set recently there is `$y$...`.
A pxx-built dropbear on such a system rejects every password login: crypt()
returns NULL, dropbear logs it and counts a failed attempt.

yescrypt is scrypt-based (Salsa20/8, PBKDF2-SHA256, a large memory-hard
core). Expect roughly a thousand lines, plus HMAC-SHA256 and PBKDF2, which
crypt.c does not have yet. Oracle: libxcrypt's crypt() on this host. bcrypt
($2b$) and MD5-crypt ($1$) are the same shape of gap and much smaller.

Not blocking [[feature-c-dropbear-builds-with-pxx]]: its acceptance test
logs in by public key.
