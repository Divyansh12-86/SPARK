/* Linker script for SPARK Boot ROM at 0x0000_0000 */
OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY
{
  rom (rx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
  .text : {
    *(.text._start)
    *(.text*)
  } > rom

  .rodata : {
    *(.rodata*)
  } > rom
}
