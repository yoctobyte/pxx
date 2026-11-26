/* <elf.h> and <link.h>: every constant crtl defines and every struct size,
   printed so the row compares them with glibc's (generated from the header
   when it was written; regenerate if names are added).
   feature-crtl-the-headers-a-hostless-target-lacks */
#include <elf.h>
#include <link.h>
#include <stdio.h>
#include <stddef.h>
int main(void) {
#ifdef EI_NIDENT
  printf("EI_NIDENT=%llx\n", (unsigned long long)(EI_NIDENT));
#else
  printf("EI_NIDENT=MISSING\n");
#endif
#ifdef EI_MAG0
  printf("EI_MAG0=%llx\n", (unsigned long long)(EI_MAG0));
#else
  printf("EI_MAG0=MISSING\n");
#endif
#ifdef EI_MAG1
  printf("EI_MAG1=%llx\n", (unsigned long long)(EI_MAG1));
#else
  printf("EI_MAG1=MISSING\n");
#endif
#ifdef EI_MAG2
  printf("EI_MAG2=%llx\n", (unsigned long long)(EI_MAG2));
#else
  printf("EI_MAG2=MISSING\n");
#endif
#ifdef EI_MAG3
  printf("EI_MAG3=%llx\n", (unsigned long long)(EI_MAG3));
#else
  printf("EI_MAG3=MISSING\n");
#endif
#ifdef EI_CLASS
  printf("EI_CLASS=%llx\n", (unsigned long long)(EI_CLASS));
#else
  printf("EI_CLASS=MISSING\n");
#endif
#ifdef EI_DATA
  printf("EI_DATA=%llx\n", (unsigned long long)(EI_DATA));
#else
  printf("EI_DATA=MISSING\n");
#endif
#ifdef EI_VERSION
  printf("EI_VERSION=%llx\n", (unsigned long long)(EI_VERSION));
#else
  printf("EI_VERSION=MISSING\n");
#endif
#ifdef EI_OSABI
  printf("EI_OSABI=%llx\n", (unsigned long long)(EI_OSABI));
#else
  printf("EI_OSABI=MISSING\n");
#endif
#ifdef EI_ABIVERSION
  printf("EI_ABIVERSION=%llx\n", (unsigned long long)(EI_ABIVERSION));
#else
  printf("EI_ABIVERSION=MISSING\n");
#endif
#ifdef EI_PAD
  printf("EI_PAD=%llx\n", (unsigned long long)(EI_PAD));
#else
  printf("EI_PAD=MISSING\n");
#endif
#ifdef ELFMAG0
  printf("ELFMAG0=%llx\n", (unsigned long long)(ELFMAG0));
#else
  printf("ELFMAG0=MISSING\n");
#endif
#ifdef ELFMAG1
  printf("ELFMAG1=%d\n", (int)ELFMAG1);
#else
  printf("ELFMAG1=MISSING\n");
#endif
#ifdef ELFMAG2
  printf("ELFMAG2=%d\n", (int)ELFMAG2);
#else
  printf("ELFMAG2=MISSING\n");
#endif
#ifdef ELFMAG3
  printf("ELFMAG3=%d\n", (int)ELFMAG3);
#else
  printf("ELFMAG3=MISSING\n");
#endif
#ifdef ELFMAG
  printf("ELFMAG=%s\n", ELFMAG);
#else
  printf("ELFMAG=MISSING\n");
#endif
#ifdef SELFMAG
  printf("SELFMAG=%llx\n", (unsigned long long)(SELFMAG));
#else
  printf("SELFMAG=MISSING\n");
#endif
#ifdef ELFCLASSNONE
  printf("ELFCLASSNONE=%llx\n", (unsigned long long)(ELFCLASSNONE));
#else
  printf("ELFCLASSNONE=MISSING\n");
#endif
#ifdef ELFCLASS32
  printf("ELFCLASS32=%llx\n", (unsigned long long)(ELFCLASS32));
#else
  printf("ELFCLASS32=MISSING\n");
#endif
#ifdef ELFCLASS64
  printf("ELFCLASS64=%llx\n", (unsigned long long)(ELFCLASS64));
#else
  printf("ELFCLASS64=MISSING\n");
#endif
#ifdef ELFCLASSNUM
  printf("ELFCLASSNUM=%llx\n", (unsigned long long)(ELFCLASSNUM));
#else
  printf("ELFCLASSNUM=MISSING\n");
#endif
#ifdef ELFDATANONE
  printf("ELFDATANONE=%llx\n", (unsigned long long)(ELFDATANONE));
#else
  printf("ELFDATANONE=MISSING\n");
#endif
#ifdef ELFDATA2LSB
  printf("ELFDATA2LSB=%llx\n", (unsigned long long)(ELFDATA2LSB));
#else
  printf("ELFDATA2LSB=MISSING\n");
#endif
#ifdef ELFDATA2MSB
  printf("ELFDATA2MSB=%llx\n", (unsigned long long)(ELFDATA2MSB));
#else
  printf("ELFDATA2MSB=MISSING\n");
#endif
#ifdef ELFDATANUM
  printf("ELFDATANUM=%llx\n", (unsigned long long)(ELFDATANUM));
#else
  printf("ELFDATANUM=MISSING\n");
#endif
#ifdef ELFOSABI_NONE
  printf("ELFOSABI_NONE=%llx\n", (unsigned long long)(ELFOSABI_NONE));
#else
  printf("ELFOSABI_NONE=MISSING\n");
#endif
#ifdef ELFOSABI_SYSV
  printf("ELFOSABI_SYSV=%llx\n", (unsigned long long)(ELFOSABI_SYSV));
#else
  printf("ELFOSABI_SYSV=MISSING\n");
#endif
#ifdef ELFOSABI_NETBSD
  printf("ELFOSABI_NETBSD=%llx\n", (unsigned long long)(ELFOSABI_NETBSD));
#else
  printf("ELFOSABI_NETBSD=MISSING\n");
#endif
#ifdef ELFOSABI_GNU
  printf("ELFOSABI_GNU=%llx\n", (unsigned long long)(ELFOSABI_GNU));
#else
  printf("ELFOSABI_GNU=MISSING\n");
#endif
#ifdef ELFOSABI_LINUX
  printf("ELFOSABI_LINUX=%llx\n", (unsigned long long)(ELFOSABI_LINUX));
#else
  printf("ELFOSABI_LINUX=MISSING\n");
#endif
#ifdef ELFOSABI_FREEBSD
  printf("ELFOSABI_FREEBSD=%llx\n", (unsigned long long)(ELFOSABI_FREEBSD));
#else
  printf("ELFOSABI_FREEBSD=MISSING\n");
#endif
#ifdef ELFOSABI_OPENBSD
  printf("ELFOSABI_OPENBSD=%llx\n", (unsigned long long)(ELFOSABI_OPENBSD));
#else
  printf("ELFOSABI_OPENBSD=MISSING\n");
#endif
#ifdef ELFOSABI_ARM
  printf("ELFOSABI_ARM=%llx\n", (unsigned long long)(ELFOSABI_ARM));
#else
  printf("ELFOSABI_ARM=MISSING\n");
#endif
#ifdef ELFOSABI_STANDALONE
  printf("ELFOSABI_STANDALONE=%llx\n", (unsigned long long)(ELFOSABI_STANDALONE));
#else
  printf("ELFOSABI_STANDALONE=MISSING\n");
#endif
#ifdef EV_NONE
  printf("EV_NONE=%llx\n", (unsigned long long)(EV_NONE));
#else
  printf("EV_NONE=MISSING\n");
#endif
#ifdef EV_CURRENT
  printf("EV_CURRENT=%llx\n", (unsigned long long)(EV_CURRENT));
#else
  printf("EV_CURRENT=MISSING\n");
#endif
#ifdef EV_NUM
  printf("EV_NUM=%llx\n", (unsigned long long)(EV_NUM));
#else
  printf("EV_NUM=MISSING\n");
#endif
#ifdef ET_NONE
  printf("ET_NONE=%llx\n", (unsigned long long)(ET_NONE));
#else
  printf("ET_NONE=MISSING\n");
#endif
#ifdef ET_REL
  printf("ET_REL=%llx\n", (unsigned long long)(ET_REL));
#else
  printf("ET_REL=MISSING\n");
#endif
#ifdef ET_EXEC
  printf("ET_EXEC=%llx\n", (unsigned long long)(ET_EXEC));
#else
  printf("ET_EXEC=MISSING\n");
#endif
#ifdef ET_DYN
  printf("ET_DYN=%llx\n", (unsigned long long)(ET_DYN));
#else
  printf("ET_DYN=MISSING\n");
#endif
#ifdef ET_CORE
  printf("ET_CORE=%llx\n", (unsigned long long)(ET_CORE));
#else
  printf("ET_CORE=MISSING\n");
#endif
#ifdef ET_NUM
  printf("ET_NUM=%llx\n", (unsigned long long)(ET_NUM));
#else
  printf("ET_NUM=MISSING\n");
#endif
#ifdef ET_LOOS
  printf("ET_LOOS=%llx\n", (unsigned long long)(ET_LOOS));
#else
  printf("ET_LOOS=MISSING\n");
#endif
#ifdef ET_HIOS
  printf("ET_HIOS=%llx\n", (unsigned long long)(ET_HIOS));
#else
  printf("ET_HIOS=MISSING\n");
#endif
#ifdef ET_LOPROC
  printf("ET_LOPROC=%llx\n", (unsigned long long)(ET_LOPROC));
#else
  printf("ET_LOPROC=MISSING\n");
#endif
#ifdef ET_HIPROC
  printf("ET_HIPROC=%llx\n", (unsigned long long)(ET_HIPROC));
#else
  printf("ET_HIPROC=MISSING\n");
#endif
#ifdef EM_NONE
  printf("EM_NONE=%llx\n", (unsigned long long)(EM_NONE));
#else
  printf("EM_NONE=MISSING\n");
#endif
#ifdef EM_SPARC
  printf("EM_SPARC=%llx\n", (unsigned long long)(EM_SPARC));
#else
  printf("EM_SPARC=MISSING\n");
#endif
#ifdef EM_386
  printf("EM_386=%llx\n", (unsigned long long)(EM_386));
#else
  printf("EM_386=MISSING\n");
#endif
#ifdef EM_68K
  printf("EM_68K=%llx\n", (unsigned long long)(EM_68K));
#else
  printf("EM_68K=MISSING\n");
#endif
#ifdef EM_MIPS
  printf("EM_MIPS=%llx\n", (unsigned long long)(EM_MIPS));
#else
  printf("EM_MIPS=MISSING\n");
#endif
#ifdef EM_PARISC
  printf("EM_PARISC=%llx\n", (unsigned long long)(EM_PARISC));
#else
  printf("EM_PARISC=MISSING\n");
#endif
#ifdef EM_PPC
  printf("EM_PPC=%llx\n", (unsigned long long)(EM_PPC));
#else
  printf("EM_PPC=MISSING\n");
#endif
#ifdef EM_PPC64
  printf("EM_PPC64=%llx\n", (unsigned long long)(EM_PPC64));
#else
  printf("EM_PPC64=MISSING\n");
#endif
#ifdef EM_S390
  printf("EM_S390=%llx\n", (unsigned long long)(EM_S390));
#else
  printf("EM_S390=MISSING\n");
#endif
#ifdef EM_ARM
  printf("EM_ARM=%llx\n", (unsigned long long)(EM_ARM));
#else
  printf("EM_ARM=MISSING\n");
#endif
#ifdef EM_SH
  printf("EM_SH=%llx\n", (unsigned long long)(EM_SH));
#else
  printf("EM_SH=MISSING\n");
#endif
#ifdef EM_SPARCV9
  printf("EM_SPARCV9=%llx\n", (unsigned long long)(EM_SPARCV9));
#else
  printf("EM_SPARCV9=MISSING\n");
#endif
#ifdef EM_IA_64
  printf("EM_IA_64=%llx\n", (unsigned long long)(EM_IA_64));
#else
  printf("EM_IA_64=MISSING\n");
#endif
#ifdef EM_X86_64
  printf("EM_X86_64=%llx\n", (unsigned long long)(EM_X86_64));
#else
  printf("EM_X86_64=MISSING\n");
#endif
#ifdef EM_XTENSA
  printf("EM_XTENSA=%llx\n", (unsigned long long)(EM_XTENSA));
#else
  printf("EM_XTENSA=MISSING\n");
#endif
#ifdef EM_AARCH64
  printf("EM_AARCH64=%llx\n", (unsigned long long)(EM_AARCH64));
#else
  printf("EM_AARCH64=MISSING\n");
#endif
#ifdef EM_RISCV
  printf("EM_RISCV=%llx\n", (unsigned long long)(EM_RISCV));
#else
  printf("EM_RISCV=MISSING\n");
#endif
#ifdef EM_BPF
  printf("EM_BPF=%llx\n", (unsigned long long)(EM_BPF));
#else
  printf("EM_BPF=MISSING\n");
#endif
#ifdef EM_LOONGARCH
  printf("EM_LOONGARCH=%llx\n", (unsigned long long)(EM_LOONGARCH));
#else
  printf("EM_LOONGARCH=MISSING\n");
#endif
#ifdef SHN_UNDEF
  printf("SHN_UNDEF=%llx\n", (unsigned long long)(SHN_UNDEF));
#else
  printf("SHN_UNDEF=MISSING\n");
#endif
#ifdef SHN_LORESERVE
  printf("SHN_LORESERVE=%llx\n", (unsigned long long)(SHN_LORESERVE));
#else
  printf("SHN_LORESERVE=MISSING\n");
#endif
#ifdef SHN_LOPROC
  printf("SHN_LOPROC=%llx\n", (unsigned long long)(SHN_LOPROC));
#else
  printf("SHN_LOPROC=MISSING\n");
#endif
#ifdef SHN_HIPROC
  printf("SHN_HIPROC=%llx\n", (unsigned long long)(SHN_HIPROC));
#else
  printf("SHN_HIPROC=MISSING\n");
#endif
#ifdef SHN_LOOS
  printf("SHN_LOOS=%llx\n", (unsigned long long)(SHN_LOOS));
#else
  printf("SHN_LOOS=MISSING\n");
#endif
#ifdef SHN_HIOS
  printf("SHN_HIOS=%llx\n", (unsigned long long)(SHN_HIOS));
#else
  printf("SHN_HIOS=MISSING\n");
#endif
#ifdef SHN_ABS
  printf("SHN_ABS=%llx\n", (unsigned long long)(SHN_ABS));
#else
  printf("SHN_ABS=MISSING\n");
#endif
#ifdef SHN_COMMON
  printf("SHN_COMMON=%llx\n", (unsigned long long)(SHN_COMMON));
#else
  printf("SHN_COMMON=MISSING\n");
#endif
#ifdef SHN_XINDEX
  printf("SHN_XINDEX=%llx\n", (unsigned long long)(SHN_XINDEX));
#else
  printf("SHN_XINDEX=MISSING\n");
#endif
#ifdef SHN_HIRESERVE
  printf("SHN_HIRESERVE=%llx\n", (unsigned long long)(SHN_HIRESERVE));
#else
  printf("SHN_HIRESERVE=MISSING\n");
#endif
#ifdef SHT_NULL
  printf("SHT_NULL=%llx\n", (unsigned long long)(SHT_NULL));
#else
  printf("SHT_NULL=MISSING\n");
#endif
#ifdef SHT_PROGBITS
  printf("SHT_PROGBITS=%llx\n", (unsigned long long)(SHT_PROGBITS));
#else
  printf("SHT_PROGBITS=MISSING\n");
#endif
#ifdef SHT_SYMTAB
  printf("SHT_SYMTAB=%llx\n", (unsigned long long)(SHT_SYMTAB));
#else
  printf("SHT_SYMTAB=MISSING\n");
#endif
#ifdef SHT_STRTAB
  printf("SHT_STRTAB=%llx\n", (unsigned long long)(SHT_STRTAB));
#else
  printf("SHT_STRTAB=MISSING\n");
#endif
#ifdef SHT_RELA
  printf("SHT_RELA=%llx\n", (unsigned long long)(SHT_RELA));
#else
  printf("SHT_RELA=MISSING\n");
#endif
#ifdef SHT_HASH
  printf("SHT_HASH=%llx\n", (unsigned long long)(SHT_HASH));
#else
  printf("SHT_HASH=MISSING\n");
#endif
#ifdef SHT_DYNAMIC
  printf("SHT_DYNAMIC=%llx\n", (unsigned long long)(SHT_DYNAMIC));
#else
  printf("SHT_DYNAMIC=MISSING\n");
#endif
#ifdef SHT_NOTE
  printf("SHT_NOTE=%llx\n", (unsigned long long)(SHT_NOTE));
#else
  printf("SHT_NOTE=MISSING\n");
#endif
#ifdef SHT_NOBITS
  printf("SHT_NOBITS=%llx\n", (unsigned long long)(SHT_NOBITS));
#else
  printf("SHT_NOBITS=MISSING\n");
#endif
#ifdef SHT_REL
  printf("SHT_REL=%llx\n", (unsigned long long)(SHT_REL));
#else
  printf("SHT_REL=MISSING\n");
#endif
#ifdef SHT_SHLIB
  printf("SHT_SHLIB=%llx\n", (unsigned long long)(SHT_SHLIB));
#else
  printf("SHT_SHLIB=MISSING\n");
#endif
#ifdef SHT_DYNSYM
  printf("SHT_DYNSYM=%llx\n", (unsigned long long)(SHT_DYNSYM));
#else
  printf("SHT_DYNSYM=MISSING\n");
#endif
#ifdef SHT_INIT_ARRAY
  printf("SHT_INIT_ARRAY=%llx\n", (unsigned long long)(SHT_INIT_ARRAY));
#else
  printf("SHT_INIT_ARRAY=MISSING\n");
#endif
#ifdef SHT_FINI_ARRAY
  printf("SHT_FINI_ARRAY=%llx\n", (unsigned long long)(SHT_FINI_ARRAY));
#else
  printf("SHT_FINI_ARRAY=MISSING\n");
#endif
#ifdef SHT_PREINIT_ARRAY
  printf("SHT_PREINIT_ARRAY=%llx\n", (unsigned long long)(SHT_PREINIT_ARRAY));
#else
  printf("SHT_PREINIT_ARRAY=MISSING\n");
#endif
#ifdef SHT_GROUP
  printf("SHT_GROUP=%llx\n", (unsigned long long)(SHT_GROUP));
#else
  printf("SHT_GROUP=MISSING\n");
#endif
#ifdef SHT_SYMTAB_SHNDX
  printf("SHT_SYMTAB_SHNDX=%llx\n", (unsigned long long)(SHT_SYMTAB_SHNDX));
#else
  printf("SHT_SYMTAB_SHNDX=MISSING\n");
#endif
#ifdef SHT_RELR
  printf("SHT_RELR=%llx\n", (unsigned long long)(SHT_RELR));
#else
  printf("SHT_RELR=MISSING\n");
#endif
#ifdef SHT_NUM
  printf("SHT_NUM=%llx\n", (unsigned long long)(SHT_NUM));
#else
  printf("SHT_NUM=MISSING\n");
#endif
#ifdef SHT_LOOS
  printf("SHT_LOOS=%llx\n", (unsigned long long)(SHT_LOOS));
#else
  printf("SHT_LOOS=MISSING\n");
#endif
#ifdef SHT_GNU_ATTRIBUTES
  printf("SHT_GNU_ATTRIBUTES=%llx\n", (unsigned long long)(SHT_GNU_ATTRIBUTES));
#else
  printf("SHT_GNU_ATTRIBUTES=MISSING\n");
#endif
#ifdef SHT_GNU_HASH
  printf("SHT_GNU_HASH=%llx\n", (unsigned long long)(SHT_GNU_HASH));
#else
  printf("SHT_GNU_HASH=MISSING\n");
#endif
#ifdef SHT_GNU_LIBLIST
  printf("SHT_GNU_LIBLIST=%llx\n", (unsigned long long)(SHT_GNU_LIBLIST));
#else
  printf("SHT_GNU_LIBLIST=MISSING\n");
#endif
#ifdef SHT_GNU_verdef
  printf("SHT_GNU_verdef=%llx\n", (unsigned long long)(SHT_GNU_verdef));
#else
  printf("SHT_GNU_verdef=MISSING\n");
#endif
#ifdef SHT_GNU_verneed
  printf("SHT_GNU_verneed=%llx\n", (unsigned long long)(SHT_GNU_verneed));
#else
  printf("SHT_GNU_verneed=MISSING\n");
#endif
#ifdef SHT_GNU_versym
  printf("SHT_GNU_versym=%llx\n", (unsigned long long)(SHT_GNU_versym));
#else
  printf("SHT_GNU_versym=MISSING\n");
#endif
#ifdef SHT_HIOS
  printf("SHT_HIOS=%llx\n", (unsigned long long)(SHT_HIOS));
#else
  printf("SHT_HIOS=MISSING\n");
#endif
#ifdef SHT_LOPROC
  printf("SHT_LOPROC=%llx\n", (unsigned long long)(SHT_LOPROC));
#else
  printf("SHT_LOPROC=MISSING\n");
#endif
#ifdef SHT_HIPROC
  printf("SHT_HIPROC=%llx\n", (unsigned long long)(SHT_HIPROC));
#else
  printf("SHT_HIPROC=MISSING\n");
#endif
#ifdef SHT_LOUSER
  printf("SHT_LOUSER=%llx\n", (unsigned long long)(SHT_LOUSER));
#else
  printf("SHT_LOUSER=MISSING\n");
#endif
#ifdef SHT_HIUSER
  printf("SHT_HIUSER=%llx\n", (unsigned long long)(SHT_HIUSER));
#else
  printf("SHT_HIUSER=MISSING\n");
#endif
#ifdef SHF_WRITE
  printf("SHF_WRITE=%llx\n", (unsigned long long)(SHF_WRITE));
#else
  printf("SHF_WRITE=MISSING\n");
#endif
#ifdef SHF_ALLOC
  printf("SHF_ALLOC=%llx\n", (unsigned long long)(SHF_ALLOC));
#else
  printf("SHF_ALLOC=MISSING\n");
#endif
#ifdef SHF_EXECINSTR
  printf("SHF_EXECINSTR=%llx\n", (unsigned long long)(SHF_EXECINSTR));
#else
  printf("SHF_EXECINSTR=MISSING\n");
#endif
#ifdef SHF_MERGE
  printf("SHF_MERGE=%llx\n", (unsigned long long)(SHF_MERGE));
#else
  printf("SHF_MERGE=MISSING\n");
#endif
#ifdef SHF_STRINGS
  printf("SHF_STRINGS=%llx\n", (unsigned long long)(SHF_STRINGS));
#else
  printf("SHF_STRINGS=MISSING\n");
#endif
#ifdef SHF_INFO_LINK
  printf("SHF_INFO_LINK=%llx\n", (unsigned long long)(SHF_INFO_LINK));
#else
  printf("SHF_INFO_LINK=MISSING\n");
#endif
#ifdef SHF_LINK_ORDER
  printf("SHF_LINK_ORDER=%llx\n", (unsigned long long)(SHF_LINK_ORDER));
#else
  printf("SHF_LINK_ORDER=MISSING\n");
#endif
#ifdef SHF_OS_NONCONFORMING
  printf("SHF_OS_NONCONFORMING=%llx\n", (unsigned long long)(SHF_OS_NONCONFORMING));
#else
  printf("SHF_OS_NONCONFORMING=MISSING\n");
#endif
#ifdef SHF_GROUP
  printf("SHF_GROUP=%llx\n", (unsigned long long)(SHF_GROUP));
#else
  printf("SHF_GROUP=MISSING\n");
#endif
#ifdef SHF_TLS
  printf("SHF_TLS=%llx\n", (unsigned long long)(SHF_TLS));
#else
  printf("SHF_TLS=MISSING\n");
#endif
#ifdef SHF_COMPRESSED
  printf("SHF_COMPRESSED=%llx\n", (unsigned long long)(SHF_COMPRESSED));
#else
  printf("SHF_COMPRESSED=MISSING\n");
#endif
#ifdef SHF_MASKOS
  printf("SHF_MASKOS=%llx\n", (unsigned long long)(SHF_MASKOS));
#else
  printf("SHF_MASKOS=MISSING\n");
#endif
#ifdef SHF_MASKPROC
  printf("SHF_MASKPROC=%llx\n", (unsigned long long)(SHF_MASKPROC));
#else
  printf("SHF_MASKPROC=MISSING\n");
#endif
#ifdef GRP_COMDAT
  printf("GRP_COMDAT=%llx\n", (unsigned long long)(GRP_COMDAT));
#else
  printf("GRP_COMDAT=MISSING\n");
#endif
#ifdef ELFCOMPRESS_ZLIB
  printf("ELFCOMPRESS_ZLIB=%llx\n", (unsigned long long)(ELFCOMPRESS_ZLIB));
#else
  printf("ELFCOMPRESS_ZLIB=MISSING\n");
#endif
#ifdef ELFCOMPRESS_ZSTD
  printf("ELFCOMPRESS_ZSTD=%llx\n", (unsigned long long)(ELFCOMPRESS_ZSTD));
#else
  printf("ELFCOMPRESS_ZSTD=MISSING\n");
#endif
#ifdef STB_LOCAL
  printf("STB_LOCAL=%llx\n", (unsigned long long)(STB_LOCAL));
#else
  printf("STB_LOCAL=MISSING\n");
#endif
#ifdef STB_GLOBAL
  printf("STB_GLOBAL=%llx\n", (unsigned long long)(STB_GLOBAL));
#else
  printf("STB_GLOBAL=MISSING\n");
#endif
#ifdef STB_WEAK
  printf("STB_WEAK=%llx\n", (unsigned long long)(STB_WEAK));
#else
  printf("STB_WEAK=MISSING\n");
#endif
#ifdef STB_NUM
  printf("STB_NUM=%llx\n", (unsigned long long)(STB_NUM));
#else
  printf("STB_NUM=MISSING\n");
#endif
#ifdef STB_LOOS
  printf("STB_LOOS=%llx\n", (unsigned long long)(STB_LOOS));
#else
  printf("STB_LOOS=MISSING\n");
#endif
#ifdef STB_GNU_UNIQUE
  printf("STB_GNU_UNIQUE=%llx\n", (unsigned long long)(STB_GNU_UNIQUE));
#else
  printf("STB_GNU_UNIQUE=MISSING\n");
#endif
#ifdef STB_HIOS
  printf("STB_HIOS=%llx\n", (unsigned long long)(STB_HIOS));
#else
  printf("STB_HIOS=MISSING\n");
#endif
#ifdef STB_LOPROC
  printf("STB_LOPROC=%llx\n", (unsigned long long)(STB_LOPROC));
#else
  printf("STB_LOPROC=MISSING\n");
#endif
#ifdef STB_HIPROC
  printf("STB_HIPROC=%llx\n", (unsigned long long)(STB_HIPROC));
#else
  printf("STB_HIPROC=MISSING\n");
#endif
#ifdef STT_NOTYPE
  printf("STT_NOTYPE=%llx\n", (unsigned long long)(STT_NOTYPE));
#else
  printf("STT_NOTYPE=MISSING\n");
#endif
#ifdef STT_OBJECT
  printf("STT_OBJECT=%llx\n", (unsigned long long)(STT_OBJECT));
#else
  printf("STT_OBJECT=MISSING\n");
#endif
#ifdef STT_FUNC
  printf("STT_FUNC=%llx\n", (unsigned long long)(STT_FUNC));
#else
  printf("STT_FUNC=MISSING\n");
#endif
#ifdef STT_SECTION
  printf("STT_SECTION=%llx\n", (unsigned long long)(STT_SECTION));
#else
  printf("STT_SECTION=MISSING\n");
#endif
#ifdef STT_FILE
  printf("STT_FILE=%llx\n", (unsigned long long)(STT_FILE));
#else
  printf("STT_FILE=MISSING\n");
#endif
#ifdef STT_COMMON
  printf("STT_COMMON=%llx\n", (unsigned long long)(STT_COMMON));
#else
  printf("STT_COMMON=MISSING\n");
#endif
#ifdef STT_TLS
  printf("STT_TLS=%llx\n", (unsigned long long)(STT_TLS));
#else
  printf("STT_TLS=MISSING\n");
#endif
#ifdef STT_NUM
  printf("STT_NUM=%llx\n", (unsigned long long)(STT_NUM));
#else
  printf("STT_NUM=MISSING\n");
#endif
#ifdef STT_LOOS
  printf("STT_LOOS=%llx\n", (unsigned long long)(STT_LOOS));
#else
  printf("STT_LOOS=MISSING\n");
#endif
#ifdef STT_GNU_IFUNC
  printf("STT_GNU_IFUNC=%llx\n", (unsigned long long)(STT_GNU_IFUNC));
#else
  printf("STT_GNU_IFUNC=MISSING\n");
#endif
#ifdef STT_HIOS
  printf("STT_HIOS=%llx\n", (unsigned long long)(STT_HIOS));
#else
  printf("STT_HIOS=MISSING\n");
#endif
#ifdef STT_LOPROC
  printf("STT_LOPROC=%llx\n", (unsigned long long)(STT_LOPROC));
#else
  printf("STT_LOPROC=MISSING\n");
#endif
#ifdef STT_HIPROC
  printf("STT_HIPROC=%llx\n", (unsigned long long)(STT_HIPROC));
#else
  printf("STT_HIPROC=MISSING\n");
#endif
#ifdef STN_UNDEF
  printf("STN_UNDEF=%llx\n", (unsigned long long)(STN_UNDEF));
#else
  printf("STN_UNDEF=MISSING\n");
#endif
#ifdef STV_DEFAULT
  printf("STV_DEFAULT=%llx\n", (unsigned long long)(STV_DEFAULT));
#else
  printf("STV_DEFAULT=MISSING\n");
#endif
#ifdef STV_INTERNAL
  printf("STV_INTERNAL=%llx\n", (unsigned long long)(STV_INTERNAL));
#else
  printf("STV_INTERNAL=MISSING\n");
#endif
#ifdef STV_HIDDEN
  printf("STV_HIDDEN=%llx\n", (unsigned long long)(STV_HIDDEN));
#else
  printf("STV_HIDDEN=MISSING\n");
#endif
#ifdef STV_PROTECTED
  printf("STV_PROTECTED=%llx\n", (unsigned long long)(STV_PROTECTED));
#else
  printf("STV_PROTECTED=MISSING\n");
#endif
#ifdef PN_XNUM
  printf("PN_XNUM=%llx\n", (unsigned long long)(PN_XNUM));
#else
  printf("PN_XNUM=MISSING\n");
#endif
#ifdef PT_NULL
  printf("PT_NULL=%llx\n", (unsigned long long)(PT_NULL));
#else
  printf("PT_NULL=MISSING\n");
#endif
#ifdef PT_LOAD
  printf("PT_LOAD=%llx\n", (unsigned long long)(PT_LOAD));
#else
  printf("PT_LOAD=MISSING\n");
#endif
#ifdef PT_DYNAMIC
  printf("PT_DYNAMIC=%llx\n", (unsigned long long)(PT_DYNAMIC));
#else
  printf("PT_DYNAMIC=MISSING\n");
#endif
#ifdef PT_INTERP
  printf("PT_INTERP=%llx\n", (unsigned long long)(PT_INTERP));
#else
  printf("PT_INTERP=MISSING\n");
#endif
#ifdef PT_NOTE
  printf("PT_NOTE=%llx\n", (unsigned long long)(PT_NOTE));
#else
  printf("PT_NOTE=MISSING\n");
#endif
#ifdef PT_SHLIB
  printf("PT_SHLIB=%llx\n", (unsigned long long)(PT_SHLIB));
#else
  printf("PT_SHLIB=MISSING\n");
#endif
#ifdef PT_PHDR
  printf("PT_PHDR=%llx\n", (unsigned long long)(PT_PHDR));
#else
  printf("PT_PHDR=MISSING\n");
#endif
#ifdef PT_TLS
  printf("PT_TLS=%llx\n", (unsigned long long)(PT_TLS));
#else
  printf("PT_TLS=MISSING\n");
#endif
#ifdef PT_NUM
  printf("PT_NUM=%llx\n", (unsigned long long)(PT_NUM));
#else
  printf("PT_NUM=MISSING\n");
#endif
#ifdef PT_LOOS
  printf("PT_LOOS=%llx\n", (unsigned long long)(PT_LOOS));
#else
  printf("PT_LOOS=MISSING\n");
#endif
#ifdef PT_GNU_EH_FRAME
  printf("PT_GNU_EH_FRAME=%llx\n", (unsigned long long)(PT_GNU_EH_FRAME));
#else
  printf("PT_GNU_EH_FRAME=MISSING\n");
#endif
#ifdef PT_GNU_STACK
  printf("PT_GNU_STACK=%llx\n", (unsigned long long)(PT_GNU_STACK));
#else
  printf("PT_GNU_STACK=MISSING\n");
#endif
#ifdef PT_GNU_RELRO
  printf("PT_GNU_RELRO=%llx\n", (unsigned long long)(PT_GNU_RELRO));
#else
  printf("PT_GNU_RELRO=MISSING\n");
#endif
#ifdef PT_GNU_PROPERTY
  printf("PT_GNU_PROPERTY=%llx\n", (unsigned long long)(PT_GNU_PROPERTY));
#else
  printf("PT_GNU_PROPERTY=MISSING\n");
#endif
#ifdef PT_HIOS
  printf("PT_HIOS=%llx\n", (unsigned long long)(PT_HIOS));
#else
  printf("PT_HIOS=MISSING\n");
#endif
#ifdef PT_LOPROC
  printf("PT_LOPROC=%llx\n", (unsigned long long)(PT_LOPROC));
#else
  printf("PT_LOPROC=MISSING\n");
#endif
#ifdef PT_HIPROC
  printf("PT_HIPROC=%llx\n", (unsigned long long)(PT_HIPROC));
#else
  printf("PT_HIPROC=MISSING\n");
#endif
#ifdef PF_X
  printf("PF_X=%llx\n", (unsigned long long)(PF_X));
#else
  printf("PF_X=MISSING\n");
#endif
#ifdef PF_W
  printf("PF_W=%llx\n", (unsigned long long)(PF_W));
#else
  printf("PF_W=MISSING\n");
#endif
#ifdef PF_R
  printf("PF_R=%llx\n", (unsigned long long)(PF_R));
#else
  printf("PF_R=MISSING\n");
#endif
#ifdef PF_MASKOS
  printf("PF_MASKOS=%llx\n", (unsigned long long)(PF_MASKOS));
#else
  printf("PF_MASKOS=MISSING\n");
#endif
#ifdef PF_MASKPROC
  printf("PF_MASKPROC=%llx\n", (unsigned long long)(PF_MASKPROC));
#else
  printf("PF_MASKPROC=MISSING\n");
#endif
#ifdef NT_PRSTATUS
  printf("NT_PRSTATUS=%llx\n", (unsigned long long)(NT_PRSTATUS));
#else
  printf("NT_PRSTATUS=MISSING\n");
#endif
#ifdef NT_PRFPREG
  printf("NT_PRFPREG=%llx\n", (unsigned long long)(NT_PRFPREG));
#else
  printf("NT_PRFPREG=MISSING\n");
#endif
#ifdef NT_FPREGSET
  printf("NT_FPREGSET=%llx\n", (unsigned long long)(NT_FPREGSET));
#else
  printf("NT_FPREGSET=MISSING\n");
#endif
#ifdef NT_PRPSINFO
  printf("NT_PRPSINFO=%llx\n", (unsigned long long)(NT_PRPSINFO));
#else
  printf("NT_PRPSINFO=MISSING\n");
#endif
#ifdef NT_AUXV
  printf("NT_AUXV=%llx\n", (unsigned long long)(NT_AUXV));
#else
  printf("NT_AUXV=MISSING\n");
#endif
#ifdef NT_GNU_ABI_TAG
  printf("NT_GNU_ABI_TAG=%llx\n", (unsigned long long)(NT_GNU_ABI_TAG));
#else
  printf("NT_GNU_ABI_TAG=MISSING\n");
#endif
#ifdef NT_GNU_HWCAP
  printf("NT_GNU_HWCAP=%llx\n", (unsigned long long)(NT_GNU_HWCAP));
#else
  printf("NT_GNU_HWCAP=MISSING\n");
#endif
#ifdef NT_GNU_BUILD_ID
  printf("NT_GNU_BUILD_ID=%llx\n", (unsigned long long)(NT_GNU_BUILD_ID));
#else
  printf("NT_GNU_BUILD_ID=MISSING\n");
#endif
#ifdef NT_GNU_GOLD_VERSION
  printf("NT_GNU_GOLD_VERSION=%llx\n", (unsigned long long)(NT_GNU_GOLD_VERSION));
#else
  printf("NT_GNU_GOLD_VERSION=MISSING\n");
#endif
#ifdef NT_GNU_PROPERTY_TYPE_0
  printf("NT_GNU_PROPERTY_TYPE_0=%llx\n", (unsigned long long)(NT_GNU_PROPERTY_TYPE_0));
#else
  printf("NT_GNU_PROPERTY_TYPE_0=MISSING\n");
#endif
#ifdef ELF_NOTE_GNU
  printf("ELF_NOTE_GNU=%s\n", ELF_NOTE_GNU);
#else
  printf("ELF_NOTE_GNU=MISSING\n");
#endif
#ifdef DT_NULL
  printf("DT_NULL=%llx\n", (unsigned long long)(DT_NULL));
#else
  printf("DT_NULL=MISSING\n");
#endif
#ifdef DT_NEEDED
  printf("DT_NEEDED=%llx\n", (unsigned long long)(DT_NEEDED));
#else
  printf("DT_NEEDED=MISSING\n");
#endif
#ifdef DT_PLTRELSZ
  printf("DT_PLTRELSZ=%llx\n", (unsigned long long)(DT_PLTRELSZ));
#else
  printf("DT_PLTRELSZ=MISSING\n");
#endif
#ifdef DT_PLTGOT
  printf("DT_PLTGOT=%llx\n", (unsigned long long)(DT_PLTGOT));
#else
  printf("DT_PLTGOT=MISSING\n");
#endif
#ifdef DT_HASH
  printf("DT_HASH=%llx\n", (unsigned long long)(DT_HASH));
#else
  printf("DT_HASH=MISSING\n");
#endif
#ifdef DT_STRTAB
  printf("DT_STRTAB=%llx\n", (unsigned long long)(DT_STRTAB));
#else
  printf("DT_STRTAB=MISSING\n");
#endif
#ifdef DT_SYMTAB
  printf("DT_SYMTAB=%llx\n", (unsigned long long)(DT_SYMTAB));
#else
  printf("DT_SYMTAB=MISSING\n");
#endif
#ifdef DT_RELA
  printf("DT_RELA=%llx\n", (unsigned long long)(DT_RELA));
#else
  printf("DT_RELA=MISSING\n");
#endif
#ifdef DT_RELASZ
  printf("DT_RELASZ=%llx\n", (unsigned long long)(DT_RELASZ));
#else
  printf("DT_RELASZ=MISSING\n");
#endif
#ifdef DT_RELAENT
  printf("DT_RELAENT=%llx\n", (unsigned long long)(DT_RELAENT));
#else
  printf("DT_RELAENT=MISSING\n");
#endif
#ifdef DT_STRSZ
  printf("DT_STRSZ=%llx\n", (unsigned long long)(DT_STRSZ));
#else
  printf("DT_STRSZ=MISSING\n");
#endif
#ifdef DT_SYMENT
  printf("DT_SYMENT=%llx\n", (unsigned long long)(DT_SYMENT));
#else
  printf("DT_SYMENT=MISSING\n");
#endif
#ifdef DT_INIT
  printf("DT_INIT=%llx\n", (unsigned long long)(DT_INIT));
#else
  printf("DT_INIT=MISSING\n");
#endif
#ifdef DT_FINI
  printf("DT_FINI=%llx\n", (unsigned long long)(DT_FINI));
#else
  printf("DT_FINI=MISSING\n");
#endif
#ifdef DT_SONAME
  printf("DT_SONAME=%llx\n", (unsigned long long)(DT_SONAME));
#else
  printf("DT_SONAME=MISSING\n");
#endif
#ifdef DT_RPATH
  printf("DT_RPATH=%llx\n", (unsigned long long)(DT_RPATH));
#else
  printf("DT_RPATH=MISSING\n");
#endif
#ifdef DT_SYMBOLIC
  printf("DT_SYMBOLIC=%llx\n", (unsigned long long)(DT_SYMBOLIC));
#else
  printf("DT_SYMBOLIC=MISSING\n");
#endif
#ifdef DT_REL
  printf("DT_REL=%llx\n", (unsigned long long)(DT_REL));
#else
  printf("DT_REL=MISSING\n");
#endif
#ifdef DT_RELSZ
  printf("DT_RELSZ=%llx\n", (unsigned long long)(DT_RELSZ));
#else
  printf("DT_RELSZ=MISSING\n");
#endif
#ifdef DT_RELENT
  printf("DT_RELENT=%llx\n", (unsigned long long)(DT_RELENT));
#else
  printf("DT_RELENT=MISSING\n");
#endif
#ifdef DT_PLTREL
  printf("DT_PLTREL=%llx\n", (unsigned long long)(DT_PLTREL));
#else
  printf("DT_PLTREL=MISSING\n");
#endif
#ifdef DT_DEBUG
  printf("DT_DEBUG=%llx\n", (unsigned long long)(DT_DEBUG));
#else
  printf("DT_DEBUG=MISSING\n");
#endif
#ifdef DT_TEXTREL
  printf("DT_TEXTREL=%llx\n", (unsigned long long)(DT_TEXTREL));
#else
  printf("DT_TEXTREL=MISSING\n");
#endif
#ifdef DT_JMPREL
  printf("DT_JMPREL=%llx\n", (unsigned long long)(DT_JMPREL));
#else
  printf("DT_JMPREL=MISSING\n");
#endif
#ifdef DT_BIND_NOW
  printf("DT_BIND_NOW=%llx\n", (unsigned long long)(DT_BIND_NOW));
#else
  printf("DT_BIND_NOW=MISSING\n");
#endif
#ifdef DT_INIT_ARRAY
  printf("DT_INIT_ARRAY=%llx\n", (unsigned long long)(DT_INIT_ARRAY));
#else
  printf("DT_INIT_ARRAY=MISSING\n");
#endif
#ifdef DT_FINI_ARRAY
  printf("DT_FINI_ARRAY=%llx\n", (unsigned long long)(DT_FINI_ARRAY));
#else
  printf("DT_FINI_ARRAY=MISSING\n");
#endif
#ifdef DT_INIT_ARRAYSZ
  printf("DT_INIT_ARRAYSZ=%llx\n", (unsigned long long)(DT_INIT_ARRAYSZ));
#else
  printf("DT_INIT_ARRAYSZ=MISSING\n");
#endif
#ifdef DT_FINI_ARRAYSZ
  printf("DT_FINI_ARRAYSZ=%llx\n", (unsigned long long)(DT_FINI_ARRAYSZ));
#else
  printf("DT_FINI_ARRAYSZ=MISSING\n");
#endif
#ifdef DT_RUNPATH
  printf("DT_RUNPATH=%llx\n", (unsigned long long)(DT_RUNPATH));
#else
  printf("DT_RUNPATH=MISSING\n");
#endif
#ifdef DT_FLAGS
  printf("DT_FLAGS=%llx\n", (unsigned long long)(DT_FLAGS));
#else
  printf("DT_FLAGS=MISSING\n");
#endif
#ifdef DT_ENCODING
  printf("DT_ENCODING=%llx\n", (unsigned long long)(DT_ENCODING));
#else
  printf("DT_ENCODING=MISSING\n");
#endif
#ifdef DT_PREINIT_ARRAY
  printf("DT_PREINIT_ARRAY=%llx\n", (unsigned long long)(DT_PREINIT_ARRAY));
#else
  printf("DT_PREINIT_ARRAY=MISSING\n");
#endif
#ifdef DT_PREINIT_ARRAYSZ
  printf("DT_PREINIT_ARRAYSZ=%llx\n", (unsigned long long)(DT_PREINIT_ARRAYSZ));
#else
  printf("DT_PREINIT_ARRAYSZ=MISSING\n");
#endif
#ifdef DT_SYMTAB_SHNDX
  printf("DT_SYMTAB_SHNDX=%llx\n", (unsigned long long)(DT_SYMTAB_SHNDX));
#else
  printf("DT_SYMTAB_SHNDX=MISSING\n");
#endif
#ifdef DT_RELRSZ
  printf("DT_RELRSZ=%llx\n", (unsigned long long)(DT_RELRSZ));
#else
  printf("DT_RELRSZ=MISSING\n");
#endif
#ifdef DT_RELR
  printf("DT_RELR=%llx\n", (unsigned long long)(DT_RELR));
#else
  printf("DT_RELR=MISSING\n");
#endif
#ifdef DT_RELRENT
  printf("DT_RELRENT=%llx\n", (unsigned long long)(DT_RELRENT));
#else
  printf("DT_RELRENT=MISSING\n");
#endif
#ifdef DT_NUM
  printf("DT_NUM=%llx\n", (unsigned long long)(DT_NUM));
#else
  printf("DT_NUM=MISSING\n");
#endif
#ifdef DT_LOOS
  printf("DT_LOOS=%llx\n", (unsigned long long)(DT_LOOS));
#else
  printf("DT_LOOS=MISSING\n");
#endif
#ifdef DT_HIOS
  printf("DT_HIOS=%llx\n", (unsigned long long)(DT_HIOS));
#else
  printf("DT_HIOS=MISSING\n");
#endif
#ifdef DT_LOPROC
  printf("DT_LOPROC=%llx\n", (unsigned long long)(DT_LOPROC));
#else
  printf("DT_LOPROC=MISSING\n");
#endif
#ifdef DT_HIPROC
  printf("DT_HIPROC=%llx\n", (unsigned long long)(DT_HIPROC));
#else
  printf("DT_HIPROC=MISSING\n");
#endif
#ifdef DT_GNU_HASH
  printf("DT_GNU_HASH=%llx\n", (unsigned long long)(DT_GNU_HASH));
#else
  printf("DT_GNU_HASH=MISSING\n");
#endif
#ifdef DT_VERSYM
  printf("DT_VERSYM=%llx\n", (unsigned long long)(DT_VERSYM));
#else
  printf("DT_VERSYM=MISSING\n");
#endif
#ifdef DT_RELACOUNT
  printf("DT_RELACOUNT=%llx\n", (unsigned long long)(DT_RELACOUNT));
#else
  printf("DT_RELACOUNT=MISSING\n");
#endif
#ifdef DT_RELCOUNT
  printf("DT_RELCOUNT=%llx\n", (unsigned long long)(DT_RELCOUNT));
#else
  printf("DT_RELCOUNT=MISSING\n");
#endif
#ifdef DT_FLAGS_1
  printf("DT_FLAGS_1=%llx\n", (unsigned long long)(DT_FLAGS_1));
#else
  printf("DT_FLAGS_1=MISSING\n");
#endif
#ifdef DT_VERDEF
  printf("DT_VERDEF=%llx\n", (unsigned long long)(DT_VERDEF));
#else
  printf("DT_VERDEF=MISSING\n");
#endif
#ifdef DT_VERDEFNUM
  printf("DT_VERDEFNUM=%llx\n", (unsigned long long)(DT_VERDEFNUM));
#else
  printf("DT_VERDEFNUM=MISSING\n");
#endif
#ifdef DT_VERNEED
  printf("DT_VERNEED=%llx\n", (unsigned long long)(DT_VERNEED));
#else
  printf("DT_VERNEED=MISSING\n");
#endif
#ifdef DT_VERNEEDNUM
  printf("DT_VERNEEDNUM=%llx\n", (unsigned long long)(DT_VERNEEDNUM));
#else
  printf("DT_VERNEEDNUM=MISSING\n");
#endif
#ifdef DF_ORIGIN
  printf("DF_ORIGIN=%llx\n", (unsigned long long)(DF_ORIGIN));
#else
  printf("DF_ORIGIN=MISSING\n");
#endif
#ifdef DF_SYMBOLIC
  printf("DF_SYMBOLIC=%llx\n", (unsigned long long)(DF_SYMBOLIC));
#else
  printf("DF_SYMBOLIC=MISSING\n");
#endif
#ifdef DF_TEXTREL
  printf("DF_TEXTREL=%llx\n", (unsigned long long)(DF_TEXTREL));
#else
  printf("DF_TEXTREL=MISSING\n");
#endif
#ifdef DF_BIND_NOW
  printf("DF_BIND_NOW=%llx\n", (unsigned long long)(DF_BIND_NOW));
#else
  printf("DF_BIND_NOW=MISSING\n");
#endif
#ifdef DF_STATIC_TLS
  printf("DF_STATIC_TLS=%llx\n", (unsigned long long)(DF_STATIC_TLS));
#else
  printf("DF_STATIC_TLS=MISSING\n");
#endif
#ifdef DF_1_NOW
  printf("DF_1_NOW=%llx\n", (unsigned long long)(DF_1_NOW));
#else
  printf("DF_1_NOW=MISSING\n");
#endif
#ifdef DF_1_GLOBAL
  printf("DF_1_GLOBAL=%llx\n", (unsigned long long)(DF_1_GLOBAL));
#else
  printf("DF_1_GLOBAL=MISSING\n");
#endif
#ifdef DF_1_NODELETE
  printf("DF_1_NODELETE=%llx\n", (unsigned long long)(DF_1_NODELETE));
#else
  printf("DF_1_NODELETE=MISSING\n");
#endif
#ifdef DF_1_NOOPEN
  printf("DF_1_NOOPEN=%llx\n", (unsigned long long)(DF_1_NOOPEN));
#else
  printf("DF_1_NOOPEN=MISSING\n");
#endif
#ifdef DF_1_ORIGIN
  printf("DF_1_ORIGIN=%llx\n", (unsigned long long)(DF_1_ORIGIN));
#else
  printf("DF_1_ORIGIN=MISSING\n");
#endif
#ifdef DF_1_PIE
  printf("DF_1_PIE=%llx\n", (unsigned long long)(DF_1_PIE));
#else
  printf("DF_1_PIE=MISSING\n");
#endif
  printf("sizeof Elf32_Ehdr=%d\n", (int)sizeof(Elf32_Ehdr));
  printf("sizeof Elf64_Ehdr=%d\n", (int)sizeof(Elf64_Ehdr));
  printf("sizeof Elf32_Shdr=%d\n", (int)sizeof(Elf32_Shdr));
  printf("sizeof Elf64_Shdr=%d\n", (int)sizeof(Elf64_Shdr));
  printf("sizeof Elf32_Chdr=%d\n", (int)sizeof(Elf32_Chdr));
  printf("sizeof Elf64_Chdr=%d\n", (int)sizeof(Elf64_Chdr));
  printf("sizeof Elf32_Sym=%d\n", (int)sizeof(Elf32_Sym));
  printf("sizeof Elf64_Sym=%d\n", (int)sizeof(Elf64_Sym));
  printf("sizeof Elf32_Rel=%d\n", (int)sizeof(Elf32_Rel));
  printf("sizeof Elf32_Rela=%d\n", (int)sizeof(Elf32_Rela));
  printf("sizeof Elf64_Rel=%d\n", (int)sizeof(Elf64_Rel));
  printf("sizeof Elf64_Rela=%d\n", (int)sizeof(Elf64_Rela));
  printf("sizeof Elf32_Phdr=%d\n", (int)sizeof(Elf32_Phdr));
  printf("sizeof Elf64_Phdr=%d\n", (int)sizeof(Elf64_Phdr));
  printf("sizeof Elf32_Nhdr=%d\n", (int)sizeof(Elf32_Nhdr));
  printf("sizeof Elf64_Nhdr=%d\n", (int)sizeof(Elf64_Nhdr));
  printf("sizeof Elf32_Dyn=%d\n", (int)sizeof(Elf32_Dyn));
  printf("sizeof Elf64_Dyn=%d\n", (int)sizeof(Elf64_Dyn));
  printf("link_map.l_addr=%d\n", (int)offsetof(struct link_map, l_addr));
  printf("link_map.l_name=%d\n", (int)offsetof(struct link_map, l_name));
  printf("link_map.l_ld=%d\n", (int)offsetof(struct link_map, l_ld));
  printf("link_map.l_next=%d\n", (int)offsetof(struct link_map, l_next));
  printf("link_map.l_prev=%d\n", (int)offsetof(struct link_map, l_prev));
  printf("ElfW=%d\n", (int)sizeof(ElfW(Sym)));
  return 0;
}
