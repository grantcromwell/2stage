ENTRY(_start)
MEMORY { OCM (rwx) : ORIGIN = 0x00010000, LENGTH = 0x0001c000 }
SECTIONS {
  .vectors : { KEEP(*(.vectors)) } > OCM
  .text : { *(.text*) *(.rodata*) } > OCM
  .data : { *(.data*) } > OCM
  .bss (NOLOAD) : { . = ALIGN(8); __bss_start__ = .; *(.bss*) *(COMMON) . = ALIGN(8); __bss_end__ = .; } > OCM
  /DISCARD/ : { *(.comment*) *(.note*) *(.ARM.exidx*) *(.ARM.extab*) }
}
