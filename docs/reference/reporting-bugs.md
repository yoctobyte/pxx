---
title: Reporting bugs
order: 94
---

# Reporting bugs

This page is for beta testers, whether you use the release archive or a clone
of the repository. It says what to check first, what to put in a report, how
to cut a program down to a small one that still shows the problem, and how to
tell a bug from something PXX does not support yet.

Reports go to the project's issue tracker:

> **Placeholder:** the address of the project's issue tracker goes here. Where
> it will be hosted has not been decided yet.

**A program that compiles and quietly gives a wrong answer is the most
valuable report you can send.** A refusal with a clear message is usually
already known; a wrong answer usually is not.

## Check the known issues first

Look for your problem on these pages before you write it up:

- [Known issues in beta 0.1](./known-issues.md): what is wrong in this
  release, with workarounds. [Silently wrong](./known-issues.md#silently-wrong)
  is at the top.
- [Current limits](./limits.md): what is not there yet, on purpose or not.
- For Nil Python, its [Known limits](../targets/nil-python.md#known-limits)
  and [Where it differs on purpose](../targets/nil-python.md#where-it-differs-on-purpose).
- For C, the [C frontend's known limitations](../targets/c-frontend.md#known-limitations).
- For Pascal, [FPC compatibility](../language/fpc-compatibility.md#important-differences).

If your problem is listed, a report is still useful when your program shows it
in a shape the page does not mention, or when the workaround does not work for
you. Say which entry you mean.

## What to put in a report

1. **Which compiler you ran.** Paste the output of:

   ```sh
   ./pxx --where | head -1
   sha256sum "$(./pxx --where | sed -n 's/^binary: *//p')"
   ```

   The first line names the compiler binary that `./pxx` runs, and the second
   gives its fingerprint. In a release archive that binary is
   `compiler/pxx-x86_64`; in a clone it is the pinned compiler. From a clone,
   add `git log -1 --format=%h` too. A later version of `pxx --version` will
   print a build identifier itself; until it does, use these lines.
2. **The exact command**, with every flag. The ones that change the result
   most are `--target=` (the CPU, or an ESP chip name such as `esp32c3`),
   `--platform=`, `--esp-profile=bare`, `-O0` to `-O3`, `--threadsafe` and
   `--system-libs`. Say whether you ran `./pxx` or a compiler binary directly:
   `./pxx` adds the library search paths, and the two can resolve an import
   differently.
3. **Where the program ran**: natively on x86-64, under QEMU
   (`tools/run_target.sh`), under wasmtime, under Espressif's QEMU, or on a
   board. For a board, give the chip and the ESP-IDF version.
4. **The smallest source file that shows the problem**, pasted in full. See
   the next section.
5. **What you expected, and what you got**, both pasted as text. The best
   "expected" is another compiler's output for the same file: GCC's for C,
   Free Pascal's for Pascal, CPython's for Nil Python. For a compile error,
   paste the whole message.
6. The output of `./pxx --doctor` if the problem is about building at all:
   a missing tool, a target that does not run, or an ESP build.

## Making a small reproducer

A report with a ten-line program gets fixed; a report that needs your whole
project often waits. To cut a program down:

1. **Save the failing version** and a script that shows the failure, such as
   a build and run whose output you compare with the expected output. Every
   cut below is judged by that script.
2. **Delete, then re-check.** Remove a routine, a unit, a class or a block of
   statements, and run the script. If the problem is still there, keep the
   cut; if it went away, undo it and try something else.
3. **Replace inputs with constants.** Replace files, command-line arguments
   and network data with literal values in the source.
4. **Inline what is left.** Move the remaining pieces of other units or files
   into one file, if the problem survives that.
5. **Stop when nothing more can go.** A good reproducer is one file, prints a
   value, and says in a comment what the value should be.

Two quick checks narrow a problem down, and are worth putting in the report:

- **Build it with `-O0`.** If the answer changes, the optimiser is involved.
- **Build it for another target** (`--target=i386`, `--target=aarch64`), and
  run it with `tools/run_target.sh`. If only one target is wrong, say which.

Make sure the small program still fails for the same reason as the original.
Cutting can move a program onto a different problem: if the message or the
wrong value changed along the way, report the one you started with, or both.

## Bug, or not supported yet?

- **The compiler refuses the program with a message that names the reason**,
  such as a feature that is not available on a target or a flag the program
  needs: that is usually a known limit, not a bug. Check the pages above. A
  report is still welcome if the message is misleading or does not say what
  to do.
- **The compiler crashes, hangs, or prints an internal error**: that is a bug,
  even if the program itself is wrong. Report it.
- **The program compiles and prints a wrong answer, or crashes where another
  compiler's build does not**: that is a bug, unless
  [Known issues](./known-issues.md) lists it or it is a documented difference
  (for Nil Python, see
  [Where it differs on purpose](../targets/nil-python.md#where-it-differs-on-purpose)).
  These are the reports that matter most.
- **A program that relies on exact CPython, GCC or Free Pascal behaviour** that
  PXX documents as different, such as the size of C `long double` or Nil
  Python's `-> int` wrapping at 64 bits: not a bug. Say so if the
  documentation did not make it clear.

## Next

- [Known issues in beta 0.1](./known-issues.md)
- [Current limits](./limits.md)
- [Command line](./cli.md)
