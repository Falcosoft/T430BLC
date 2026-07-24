# Reverse-engineering history

## Initial direction: Intel OpRegion and ACPI

The investigation began with Intel graphics OpRegion discovery and ACPI methods related to brightness. PCI ASLS and the system DSDT were examined, including brightness-related methods and mailbox fields. These structures were useful for understanding firmware communication but did not expose the live PWM duty used by the panel.

## Locating the active PWM path

Graphics MMIO registers were sampled while the hardware brightness keys changed the panel level. The legacy offsets did not change, while `48254h` tracked the duty level and `C8254h` exposed the maximum in its upper word.

## Protected-mode MMIO access

Real mode cannot directly address MMIO near `F0000000h`. A temporary protected-mode environment was therefore developed with a flat data descriptor and explicit 32-bit address/operand overrides.

A critical early failure caused immediate hardware resets. The cause was a write through `CS:` while the code selector was executable but not writable. With no protected-mode IDT, the resulting general-protection fault escalated into a triple fault and reset. Moving variable writes to a writable `ES` descriptor fixed the problem.

A read-only diagnostic then confirmed that protected-mode entry, flat addressing, and MMIO reads all worked on the physical T430.

## Writer validation

The final writer changes only the low 16-bit duty field of `BAR0+48254h`, preserves the upper word, and performs immediate readback verification. This became `BLCSET`.

## Boot-time driver

The original goal was to avoid repeatedly pressing Fn+F8 at every DOS boot. A CONFIG.SYS device driver was therefore built to run after HIMEM.SYS and before EMM386. It performs the same temporary protected-mode transition once during initialization and then releases nearly all its memory.

Two driver-specific bugs were identified and corrected:

1. The SYS file had to be linked as an EXE and converted with EXE2BIN; `TLINK /t` is only for COM files.
2. BIOS hexadecimal output changed `BL` to color value `07h`, producing displays such as `1155` → `1757`. Preserving `BX` in `PrintNibble` fixed reporting without changing the PWM operation.

The final BLCINIT driver was successfully tested at MS-DOS boot on the target T430.
