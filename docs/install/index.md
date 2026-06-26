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
