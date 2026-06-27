# Native Debug Tools

Use this when investigating generated ELF crashes, C frontend runtime bugs, or
Lua/SQLite bring-up failures.

## Available on this system

Checked 2026-06-27:

- `gdb`: installed; ptrace works. Breakpoints and watchpoints are usable. The
  generated Lua ELF may print a dynamic-linker probe warning, but gdb still works.
- `systemd-coredump` / `coredumpctl`: installed. Use `coredumpctl list`, then
  `coredumpctl gdb <program>` for post-crash inspection.
- `gdbserver`: installed for remote/container debugging.
- `strace`: installed for syscall traces.
- `ltrace`: installed for dynamic-library call traces. Less useful for mostly
  static/generated binaries, useful when dynamic imports are involved.
- `elfutils`: installed; useful commands include `eu-stack` and `eu-readelf`.
- `heaptrack`: installed for allocation profiling.
- `rr`: installed (`rr 5.7.0`), but currently blocked by kernel perf policy:
  `/proc/sys/kernel/perf_event_paranoid` is `4`, and `rr record -n` failed with
  `perf_event_open` permission denied. Recheck after sysctl changes.

## Frankonpiler Generated ELF Notes

- Generated ELFs can have sparse or unusual section metadata, so `objdump -d`
  is often less useful than gdb disassembly after loading the program:
  `x/80i 0xADDR`.
- For Lua, regenerate the compiler proc map after rebuilds:

  ```sh
  ./compiler/pascal26 --debug \
    -Ilib/crtl/include -Ilib/crtl/src -Ilibrary_candidates/lua/src \
    library_candidates/lua/src/pxx_hostamalg.c /tmp/luah_dbg_current \
    > /tmp/luah_debug_current.log 2>&1
  ```

- In recent generated Linux/x86-64 ELFs, runtime address mapping was:
  `runtime address - 0x400078 = CodePos`. Verify the load base after rebuilds.
  Then find the nearest `proc ... at` entry in `/tmp/luah_debug_current.log`.
- Useful gdb forms:

  ```gdb
  set debuginfod enabled off
  set pagination off
  set language c
  break *0xADDR
  watch *(long*)0xADDR
  x/32gx 0xADDR
  x/80i 0xADDR
  ```

- If a normal-stack run segfaults with `%rsp` near the stack guard page, rerun
  with unlimited stack to distinguish stack exhaustion from an immediate bad
  pointer fault:

  ```sh
  (ulimit -s unlimited; timeout 10s /tmp/luah_pxx \
    > /tmp/luah_pxx.unlim.stdout 2> /tmp/luah_pxx.unlim.stderr)
  ```

## Lua Bring-Up Commands

Compile:

```sh
./compiler/pascal26 -g \
  -Ilib/crtl/include -Ilib/crtl/src -Ilibrary_candidates/lua/src \
  library_candidates/lua/src/pxx_hostamalg.c /tmp/luah_pxx
```

Run:

```sh
timeout 10s /tmp/luah_pxx > /tmp/luah_pxx.stdout 2> /tmp/luah_pxx.stderr
```
