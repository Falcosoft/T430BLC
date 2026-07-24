# Changelog

## 1.0.0 — 2026-07-24

- Added `BLCSET.COM` command-line PWM setter.
- Added `BLCINIT.SYS` boot-time CONFIG.SYS initializer.
- Dynamically discovers Intel graphics BAR0 through PCI BIOS.
- Reads the PWM maximum from `BAR0+C8254h`.
- Preserves the upper word of `BAR0+48254h` and verifies writes by readback.
- Added safe real-mode/protected-mode transitions using XMS for A20 control.
- Added boot-driver private-stack handling and discardable initialization section.
- Corrected SYS linking instructions and hexadecimal reporting.
- Added complete technical documentation and attribution.
