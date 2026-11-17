/* A position-independent xtensa program in the shape Gibux's loader takes
   (ESP32-S3, no MMU): ET_DYN from address 0, no PT_INTERP, code and its
   literals alone in an R+X PT_LOAD, everything read as data in an RW one.
   .init_array with its bounds is REQUIRED: pxx objects fill their globals
   from it. Link: ld -pie --no-dynamic-linker -T this. tools/check_xtensa_pie_link.py */
PHDRS {
  text PT_LOAD FILEHDR PHDRS FLAGS(5);
  data PT_LOAD FLAGS(6);
  dynamic PT_DYNAMIC;
}
ENTRY(_start)
SECTIONS {
  . = SIZEOF_HEADERS;
  .text : ALIGN(4) { *(.literal .literal.* .text .text.*) } :text
  . = ALIGN(16);
  .hash : { *(.hash) } :data
  .dynsym : { *(.dynsym) }
  .dynstr : { *(.dynstr) }
  .rela.dyn : { *(.rela.*) }
  .rodata : { *(.rodata .rodata.*) }
  /* each pxx object's initialiser slot; crtl's __pxx_run_initializers walks
     the bounds before main (feature-xtensa-objects-run-their-initialisers) */
  .init_array : {
    PROVIDE_HIDDEN(__init_array_start = .);
    KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*) .init_array))
    PROVIDE_HIDDEN(__init_array_end = .);
  }
  .dynamic : { *(.dynamic) } :data :dynamic
  .got : { *(.got .got.*) } :data
  .data : { *(.data .data.*) }
  .bss : { *(.bss .bss.* COMMON) }
  .xt.lit 0 : { *(.xt.lit .xt.lit.*) }
  /DISCARD/ : { *(.comment) *(.note.*) }
}
