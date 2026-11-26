/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <link.h>, the dynamic linker's view of loaded objects: ElfW(),
 * struct link_map (what dlinfo(RTLD_DI_LINKMAP) hands back), and struct
 * dl_phdr_info. A pxx program is linked without a dynamic loader, so crtl's
 * dlinfo fails (dlfcn.h says so) and there is no dl_iterate_phdr; this
 * header is the types only, so code that uses them when it finds them at run
 * time (rumpuser_dl.c) compiles and takes its failure path.
 */
#ifndef _CRTL_LINK_H
#define _CRTL_LINK_H
#include <elf.h>
#include <dlfcn.h>
#include <stddef.h>

#if __SIZEOF_POINTER__ == 8
#define __ELF_NATIVE_CLASS 64
#else
#define __ELF_NATIVE_CLASS 32
#endif
#define ElfW(type) _ElfW(Elf, __ELF_NATIVE_CLASS, type)
#define _ElfW(e, w, t) _ElfW_1(e, w, _##t)
#define _ElfW_1(e, w, t) e##w##t

struct link_map {
  ElfW(Addr) l_addr;          /* load bias: file addresses + l_addr */
  char *l_name;               /* the object's path, "" for the main program */
  ElfW(Dyn) *l_ld;            /* its dynamic section */
  struct link_map *l_next, *l_prev;
};

struct dl_phdr_info {
  ElfW(Addr) dlpi_addr;
  const char *dlpi_name;
  const ElfW(Phdr) *dlpi_phdr;
  ElfW(Half) dlpi_phnum;
};

#endif
