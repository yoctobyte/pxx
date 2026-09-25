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

The full history is large (about 1 GB on disk). If you only want to use the
compiler, a shallow clone carries everything needed, including the pinned
compiler, and takes seconds instead of minutes:

```sh
git clone --depth 1 https://github.com/yoctobyte/pxx
```

`./install.sh` checks that the pinned compiler runs, writes the `./pxx`
wrapper, and then asks up to five optional questions. Each defaults to no except the
last, which opens the demo launcher:

```text
Put pxx on your PATH (~/.local/bin)? [y/N]
Fetch & configure Synapse (networking: HTTP/FTP/SMTP, blocking clients)? [y/N]
Install the ESP32 IDF toolchain (bare-metal / xtensa+riscv32 targets)? [y/N]
Build the Eliah IDE (needs GTK3 dev libs)? [y/N]
Explore the example apps now (./demos.sh)? [Y/n]
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

`--yes` answers no to every optional step and does not open the demo launcher;
it ends by printing `run ./demos.sh to explore the example apps`. The launcher
is also skipped when no terminal is attached, as in a script or CI.

## From a release archive

A release archive holds the source, the libraries, the examples and these
docs, plus a prebuilt compiler for each host (`compiler/pxx-x86_64`, `-i386`,
`-aarch64`, `-arm32`). It has no `stable_linux_amd64/` pinned compiler; the
steps below set up the prebuilt one instead. From the
directory you downloaded it to:

```sh
sha256sum -c SHA256SUMS            # with the .tar.gz beside it
tar xzf pxx-<version>.tar.gz && cd pxx-<version>
./install.sh --yes                 # writes ./pxx, the wrapper every page here uses
./pxx test/hello.pas /tmp/hello && /tmp/hello
./setup.sh                         # points compiler/pxx at this host's binary
./selfcheck.sh                     # needs ./setup.sh first
```

`./setup.sh` also offers to link `pxx` into `~/.local/bin` when run at a
terminal. `./selfcheck.sh` stops with `no compiler/pxx — run ./setup.sh first`
if you skip that step. `tools/install.sh`, below, works in a checkout only.

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
source file. From the checkout they are:

```sh
./pxx --where     # every path this binary resolves, and which tier set it
./pxx --doctor    # what this box can do: cross-run, ESP, gdb, FPC seed, gcc
```

Once the wrapper is on your `PATH`, plain `pxx` works the same.

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
anywhere without installing a wrapper. With the archive unpacked as `/opt/pxx`:

```sh
PXX_HOME=/opt/pxx /opt/pxx/compiler/pxx-x86_64 hello.pas hello
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

Install QEMU user-mode helpers for Linux cross-target smoke runs. This installs
system packages with `apt-get` (Debian or Ubuntu), so it asks for `sudo`:

```sh
tools/install_qemu.sh
```

`./pxx --doctor` shows which emulators are already present.

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

`make bootstrap` builds the compiler with FPC, rebuilds it with itself, and
checks that two successive self-built stages are byte-identical; it takes about
a minute. It installs the result as `compiler/pascal26`. The pinned compiler,
which `./pxx` uses, is left alone. `make test` is the full test suite and takes
considerably longer.

You only need FPC for bootstrap or recovery builds. Normal use of a checkout can
run through the pinned compiler.

## Next

- [Getting started](../getting-started/)
- [Command-line reference](../reference/cli.md)
