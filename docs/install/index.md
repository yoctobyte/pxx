---
title: Install
order: 10
---

# Install

A fresh checkout ships a pinned stable compiler, so the normal setup path does
not require Free Pascal or a system toolchain.

```sh
git clone https://github.com/yoctobyte/pxx
cd pxx
./install.sh
```

## Official sources

There are exactly two, and there is no third:

- **Website** — <https://pxxc.org>
- **Source** — <https://github.com/yoctobyte/pxx>

PXX is installed by cloning that repository — there is no installer to download,
no package in a distro repository, and no binary release channel yet. Anything
offering a PXX download from another address is not us. When signed releases do
exist, the signing key's fingerprint will be published here and on the website,
and verifying against it will be the check that matters — not the address you
got the file from.

### What a release will carry, and how to check it

No release has been cut yet, so there is nothing to verify today. When one is
published it will carry two separate files, answering two different questions —
worth knowing apart, because only the second is unusual:

- **`SHA256SUMS`** — the checksum of the archive itself, published in the
  GitHub Release. Check it **before extracting**:

  ```sh
  sha256sum -c SHA256SUMS      # with the .tar.gz beside it
  ```

  This answers *is this the archive we published?* A site impersonating this
  project can copy a page; it cannot make its tarball match a hash published in
  a repository it does not control.

- **`selfcheck.sh`** — shipped inside the bundle, beside `MANIFEST.sha256`. It
  recompiles every prebuilt binary **on your machine, from the source in the
  same bundle**, and diffs the result against the manifest.

  ```sh
  ./selfcheck.sh
  ```

  This answers the harder question — *are the binaries I was given the ones this
  source produces?* — and it is a check most compilers cannot offer, because
  PXX's build is a byte-identical self-host fixed point. It is a statement about
  determinism of *our own* build; it is not a comparison against any other
  compiler's output.

The archive itself is not byte-reproducible (gzip records an mtime, and the
binaries are built fresh), which is exactly why both files exist: `SHA256SUMS`
pins the artifact, `selfcheck.sh` proves its contents. A **signature** over
`SHA256SUMS` is the remaining piece and is not in place yet; until it is,
`SHA256SUMS` is only as trustworthy as the repository serving it.

The root `install.sh` is the friendly setup script. It verifies that a compiler
can run on the host, writes a ready-to-use `./pxx` wrapper in the project root,
and optionally offers to install a PATH wrapper, fetch external libraries,
install ESP32 tooling, build the Eliah IDE, and run demos.

For unattended setup:

```sh
./install.sh --yes
```

## Wrapper installs

The wrapper calls the pinned compiler and adds the project library roots, so a
plain command can find bundled RTL/PCL units from any working directory:

```sh
./pxx hello.pas hello
```

The lower-level `tools/install.sh` only creates or removes a wrapper. Use it when
the checkout is already set up and you only want to change where `pxx` is found:

```sh
tools/install.sh --bindir "$HOME/.local/bin"
```

To remove that wrapper:

```sh
tools/install.sh --uninstall
```

The generated wrapper embeds the current library search roots. Re-run
`tools/install.sh` after moving the checkout or after adding new library
directories that should be visible to every compile.

## Checking an install, and fixing "unit source not found"

Two commands answer almost every question about an install, and neither needs a
source file:

```sh
pxx --where     # every path this binary resolves, and which tier set it
pxx --doctor    # what this box can do: cross-run, ESP, gdb, FPC seed, gcc
```

**`unit source not found` is the usual first failure**, and `--where` is the
one-command answer. It prints the roots from the code that resolves them and
marks each one that does not exist `[MISSING]`, so a wrong root is visible
rather than inferred:

```
Library roots (as ParseUsesUnit resolves them):
  /opt/pxx/lib/rtl/   [MISSING]   [RTL]
```

`pxx --doctor` answers the other half — what is *available* rather than where it
is. Nothing it reports is fatal: compiling and running a native program needs
none of the optional rows, and every `no` costs exactly the capability its row
names.

### Running from an unpacked tarball: `PXX_HOME`

Called directly, the compiler guesses its library roots from its own directory.
`PXX_HOME` replaces that guess, and is what makes an unpacked tarball work from
anywhere without installing a wrapper:

```sh
PXX_HOME=/opt/pxx /opt/pxx/bin/pascal26 hello.pas hello
```

(A wrapper made by `tools/install.sh` passes its bundled roots as `-Fu`, and
those outrank `PXX_HOME` — so set one or use the other, not both.)

It is honoured **all-or-nothing** — the exe-dir guesses are *not* kept
underneath it as a fallback — so pointing it at the wrong root replaces working
paths with broken ones and the RTL stops resolving. If a build breaks right
after you set it, run `pxx --where`.

`PXX_LIBPATH=a:b` adds extra unit roots without replacing anything, and a
`pxx.cfg` can set the same things persistently. Both are covered in the
[command-line reference](../reference/cli.md#environment-and-pxxcfg).

## Optional libraries and tools

The default checkout is self-contained. Extra source trees and vendor SDKs are
installed on demand and stay outside git-tracked source.

Fetch candidate third-party libraries used for compatibility experiments:

```sh
tools/install_lib_candidates.sh
tools/install_lib_candidates.sh lua
tools/install_lib_candidates.sh tiny-regex-c freebsd-regex
```

The fetched trees go under `library_candidates/`, which is gitignored by policy.
Use `FORCE=1` to refresh an existing candidate:

```sh
FORCE=1 tools/install_lib_candidates.sh lua
```

Install QEMU user-mode helpers for Linux cross-target smoke runs:

```sh
tools/install_qemu.sh
```

ESP32 setup is larger because it pulls vendor tooling. The root installer offers
it interactively; after installation, source the ESP-IDF environment printed by
the tool before using the ESP32 helpers.

## Building from source

PXX is self-hosting, but a recovery bootstrap can seed it from Free Pascal:

```sh
sudo apt install fpc make
make bootstrap
make test
```

You only need FPC for bootstrap or recovery builds. Normal use of a checkout can
run through the pinned compiler.

## Next

- [Getting started](../getting-started/)
- [Command-line reference](../reference/cli.md)
