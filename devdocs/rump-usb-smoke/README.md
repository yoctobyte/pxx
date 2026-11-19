# NetBSD rump USB (xhci, usb, umass, scsipi, disk) from pxx objects

Measured 2026-11-19 (rd), pxx `latest-80a4e4812c`, NetBSD 6e3f6e42f352.

## Result

Every compile of the gcc build, 353 of them, compiles under pxx. The ten
archives were rebuilt from pxx objects, 341/341 members:
librumpdev_umass, _scsipi, _disk, _usb, _pci_usbhc, _pci, librumpdev,
librumpvfs_nofifofs, librumpvfs and librump. Only librumpuser is gcc's, as
for rumpnic. The smoke program `usbsmoke.c` with `xhcistub.c` boots that
rump kernel. Its console is **line for line the same as the gcc build's**
(timestamps aside, and the spelling of the panic's source path; see the end):

    pci0 at mainbus0 bus 0
    xhci0 at pci0 dev 0 function 0: vendor 1b36 product 000d (rev. 0x01)
    xhci0: 64-bit DMA
    xhci0: xHCI version 1.10
    usb0 at xhci0: USB revision 3.0
    panic: kernel diagnostic assertion "xfer->ux_bus->ub_usedma == false" failed: ... usbdi.c, line 560

The panic is the stub's limit, not pxx's. The stub has no command ring, so
the root hub's first transfer has nothing behind it, and gcc's objects stop
at the same assertion. umass and sd need a device behind a working
controller: a real xHCI (QEMU qemu-xhci + usb-storage through vfio), which
this host-only test does not have.

## How

1. A gcc rump build with the USB directories. This used a copy of
   Rainyday's `tools/rump-build.sh` (not reproduced here; Rainyday is
   private), with `SRC=` set to the rumpnic build tree and two changes. The
   directory list became lib/librumpuser, lib/librump, lib/librumpdev,
   lib/librumpvfs, and sys/rump/dev/lib/{libpci, libpci_usbhc, libusb,
   libumass, libscsipi, libdisk}, plus sys/rump/fs/lib/libnofifovfs (its
   fifo stubs are needed to link). The rumpnic components and archive check
   were dropped. The result is 353 compiles in cc-commands.log.
2. `pxxcc_s2.py LOG OUT --freestanding --system-libs -include
   gcc-predef.h -include layer-none.h` with PXX set to the published
   compiler (frank-user's harness, ~/rump-pxx-work, copied; the shims are
   Rainyday's docs/rump-pxx/harness).
3. `mkarch2.py LOG GCCOBJ OUT WORK <the ten archives>`: the same members,
   the same order, the same `rumpns_` renaming.
4. `gcc -no-pie usbsmoke.c xhcistub.c -Wl,--whole-archive <archives>
   -Wl,--no-whole-archive librumpuser.a -lpthread -ldl`, then run it with
   `RUMP_VERBOSE=1`.

`xhcistub.c` also defines `rumpns_bus_dmatag_subregion`, which ehci_init
calls and rump's libpci lacks.

A path difference in the panic line comes from the harness, not the
compiler: pxxcc_s2.py normalises the source path, and `__FILE__` follows
it. Given the same spelling, pxx's `__FILE__` matches gcc's.
