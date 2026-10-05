---
track: A
prio: 70
type: regression
blocked-by: []
summary: "Since 0a21c18151 (extern variables), some plain C function prototypes from a uses-imported header are emitted as 4-byte GLOBAL .bss definitions in an ESP object (nm: 'B malloc', 'B imaxabs'). IDF's link then fails: multiple definition of 'malloc' / 'valloc' vs libesp_libc.a(heap.o). 885d670ba2 linked fine. Blocks museum_landkaart/async firmware."
status: done
owner: ""
---

# Imported C prototypes become global .bss symbols on ESP

## Repro (riscv32 ESP object, no IDF needed)

```sh
cat > rh.h <<'H'
typedef long long intmax_t;
typedef unsigned int size_t;
intmax_t imaxabs(intmax_t);
void *malloc(size_t);
int plainfn(int);
extern int g_x;
H
cat > rp.pas <<'P'
program rp;
uses rh;
function Get: Integer; cdecl;
begin
  Result := g_x;
end;
begin
end.
P
pascal26 --target=riscv32 --platform=esp --no-signals --emit-obj -I. -Fu. rp.pas rp.o
riscv32-esp-elf-nm rp.o | grep -E "imaxabs|malloc|plainfn|g_x"
#   000055f0 B imaxabs
#   000055f8 B malloc
```

`plainfn` correctly emits nothing; `imaxabs` and `malloc` (names the RTL/libc
layer also knows?) become 4-byte global data. In the real app (src/idf.h, the
full picolibc) the set is: alloca, arc4random_uniform, getpgid, getsid,
imaxabs, malloc, valloc. All are ordinary prototypes, e.g. picolibc stdlib.h:183
`void *malloc(size_t) __malloc_like ...;`, inttypes.h:326 `intmax_t imaxabs(intmax_t);`.

Also odd: `g_x` (extern int, read in a cdecl routine) does not appear as UND
in this repro; maybe Get was dropped as unreachable, so check that too.

## Effect

```
ld: libpxx_app.a(main.o):(.bss+0x5600): multiple definition of `malloc';
    esp-idf/esp_libc/libesp_libc.a(heap.o): first defined here
ld: libpxx_app.a(main.o):(.bss+0x5604): multiple definition of `valloc'; ...
```
Had it linked, every C call to malloc would have jumped into .bss.

## Acceptance

nm of rp.o shows no imaxabs/malloc definitions, and museum_landkaart/async
`./build.sh qemu-test` links and passes on master.

## Log
- 2026-10-05: filed from museum_landkaart/async; found when re-running after 0a21c18151.
