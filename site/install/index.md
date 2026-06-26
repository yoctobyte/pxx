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

`install.sh` verifies that a compiler can run on the host, writes a ready-to-use
`./pxx` wrapper in the project root, and optionally offers to install a PATH
wrapper, fetch external libraries, install ESP32 tooling, build the Eliah IDE,
and run demos.

For unattended setup:

```sh
./install.sh --yes
```

## What gets installed

The wrapper calls the pinned compiler and adds the project library roots, so a
plain command can find bundled RTL/PCL units from any working directory:

```sh
./pxx hello.pas hello
```

To install only the wrapper into another directory:

```sh
tools/install.sh --bindir "$HOME/.local/bin"
```

To remove that wrapper:

```sh
tools/install.sh --uninstall
```

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
