/* A one-device PCI bus for a host-only rump smoke test (rumpcomp_pci_*): bus 0
   dev 0 fn 0 is QEMU's xHCI (1b36:000d, class 0c0330), BAR0 a 64 KiB memory BAR
   backed by host memory with a plausible capability block, and a thread that
   gives HCRST/HCHalted their side effects. xhci0 and usb0 attach; the root
   hub's first transfer then trips usbdi.c's ub_usedma assertion (no command
   ring behind it), with gcc's objects and pxx's alike. Everything else on
   the bus answers "no device". See README.md. */
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>

static unsigned int cfg[64];
static int cfg_ready;
static void *bar0;

static void cfg_init(void)
{
  if (cfg_ready) return;
  cfg_ready = 1;
  cfg[0] = 0x000d1b36u;          /* device 000d, vendor 1b36 */
  cfg[1] = 0x00100006u;          /* status: cap list; command: mem + master */
  cfg[2] = 0x0c033001u;          /* class 0c (serial bus) 03 (USB) 30 (xHCI), rev 1 */
  cfg[3] = 0x00000000u;
  cfg[4] = 0xfebf0004u;          /* BAR0: memory, 64-bit */
  cfg[5] = 0x00000000u;
  cfg[11] = 0x11001af4u;         /* subsystem */
  cfg[15] = 0x0000010bu;         /* interrupt pin A, line 11 */
}

int rumpcomp_pci_confread(unsigned b, unsigned d, unsigned f, int r, unsigned int *v)
{
  cfg_init();
  if (b != 0 || d != 0 || f != 0 || r < 0 || r >= 256) { *v = 0xFFFFFFFFu; return 0; }
  *v = cfg[r / 4];
  return 0;
}

int rumpcomp_pci_confwrite(unsigned b, unsigned d, unsigned f, int r, unsigned int v)
{
  cfg_init();
  if (b != 0 || d != 0 || f != 0 || r < 0 || r >= 256) return 0;
  if (r == 0x10) { cfg[4] = (v == 0xFFFFFFFFu) ? 0xFFFF0004u : (v & ~0xFu) | 4u; return 0; }
  if (r == 0x14) { cfg[5] = (v == 0xFFFFFFFFu) ? 0xFFFFFFFFu : v; return 0; }
  cfg[r / 4] = v;
  return 0;
}

/* The few register side effects xhci_init waits for: HCRST clears itself
   (and CNR), and HCHalted follows Run/Stop. No command ring, no ports. */
static void *hc_emul(void *arg)
{
  volatile unsigned int *w = arg;
  for (;;) {
    unsigned int cmd = w[0x20 / 4];
    if (cmd & 2u) w[0x20 / 4] = cmd & ~2u;
    w[0x24 / 4] = (w[0x24 / 4] & ~0x801u) | ((w[0x20 / 4] & 1u) ? 0u : 1u);
    usleep(500);
  }
  return 0;
}

void *rumpcomp_pci_map(unsigned long a, unsigned long l)
{
  if (!bar0) {
    unsigned int *w = calloc(1, 65536);
    bar0 = w;
    /* capability registers: CAPLENGTH 0x20, HCIVERSION 1.1 */
    w[0x00 / 4] = 0x01100020u;
    w[0x04 / 4] = (4u << 24) | (1u << 8) | 8u;   /* HCSPARAMS1: 4 ports, 1 intr, 8 slots */
    w[0x10 / 4] = (0x40u << 16) | 1u;            /* HCCPARAMS1: xECP at 0x100, AC64 */
    w[0x14 / 4] = 0x2000u;                       /* DBOFF */
    w[0x18 / 4] = 0x1000u;                       /* RTSOFF */
    /* operational registers at 0x20: USBSTS HCHalted, PAGESIZE 4 KiB */
    w[0x24 / 4] = 1u;
    w[0x28 / 4] = 1u;
    /* supported protocol capabilities: USB 2.0 ports 1-2, USB 3.0 ports 3-4 */
    w[0x100 / 4] = (2u << 24) | (4u << 8) | 2u;
    w[0x104 / 4] = 0x20425355u;                  /* "USB " */
    w[0x108 / 4] = (2u << 8) | 1u;
    w[0x110 / 4] = (3u << 24) | 2u;
    w[0x114 / 4] = 0x20425355u;
    w[0x118 / 4] = (2u << 8) | 3u;
    { pthread_t t; pthread_create(&t, 0, hc_emul, w); pthread_detach(t); }
  }
  fprintf(stderr, "xhcistub: map %#lx len %#lx\n", a, l);
  return bar0;
}

int rumpcomp_pci_irq_map(unsigned b, unsigned d, unsigned f, int l, unsigned c) { return 0; }
void *rumpcomp_pci_irq_establish(unsigned c, int (*h)(void *), void *a) { return (void *)1; }
int rumpcomp_pci_dmalloc(size_t s, size_t al, unsigned long *p, unsigned long *v)
{
  void *m = aligned_alloc(al < 4096 ? 4096 : al, (s + 4095) & ~(size_t)4095);
  if (!m) return 1;
  memset(m, 0, s);
  *p = (unsigned long)m; *v = (unsigned long)m;
  return 0;
}
void rumpcomp_pci_dmafree(unsigned long v, size_t s) { free((void *)v); }
struct rumpcomp_pci_dmaseg { unsigned long ds_pa, ds_len, ds_vacookie; };
/* identity "physical" memory: one segment maps to its own address */
int rumpcomp_pci_dmamem_map(struct rumpcomp_pci_dmaseg *s, size_t n, size_t t, void **v)
{
  if (n != 1) return 1;
  *v = (void *)s[0].ds_vacookie;
  return 0;
}
unsigned long rumpcomp_pci_virt_to_mach(void *va) { return (unsigned long)va; }

/* ehci_init calls it; rump's libpci has no bus_dma subregions. Only ehci
   uses it and the stub bus has no EHCI, so "not supported" (EOPNOTSUPP). */
int rumpns_bus_dmatag_subregion(void *tag, unsigned long min, unsigned long max, void **newtag, int flags)
{
  return 45;
}
