# Changelog

All notable changes to T430LCD are documented here.

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


The project originally appeared as **T430BLC**. The T430LCD name was adopted when the scope expanded from backlight control to broader LCD and display-engine control.

## [2.0.0] — Planned public release

### Project

- Renamed T430BLC to T430LCD.
- Reorganized the project into user tools, diagnostics, and documentation.
- Retained the MIT License.
- Added explicit documentation of the collaborative development process.
- Added a dedicated Vogons community discussion.

### ASPECT

- Added resident automatic 4:3 aspect-ratio correction.
- Added interception of legacy VGA mode sets through `INT 10h AH=00h`.
- Added interception of VESA mode sets through `INT 10h AX=4F02h`.
- Confirmed operation with Duke Nukem 3D and Descent under plain DOS.
- Added safe virtual-8086 detection.
- Added dynamic fitter-destination detection.
- Added centered 4:3 window calculation.
- Added native VESA mode exception.
- Added conservative fixed-raster detection.
- Added automatic skip when the BIOS output is already 4:3.
- Added automatic skip when the fitter destination changes between modes.
- Added correct behavior for internal LCD, external analog VGA, and external DVI.
- Added safe `/U` unloading.
- Added interrupt-chain ownership checks before unloading.
- Added restoration of original `INT 10h` and `INT 2Fh` vectors.
- Added release of resident environment and PSP memory blocks.
- Confirmed that only `PF_A_POS` and `PF_A_SIZE` should be written.
- Confirmed that rewriting `PF_A_CTL` can cause flickering and corrupted output.

### Diagnostics

- Added FITREAD for Intel OpRegion panel-fitting inspection.
- Added PFDIAG for all Ivy Bridge panel-fitter blocks.
- Added PFSNAP read-only TSR for before/after BIOS mode-change snapshots.
- Added pipe timing and source-size capture.
- Documented fixed-raster internal LCD behavior versus mode-timed external outputs.

### Future work

- DPMI-compatible MMIO access under EMM386.
- Compatibility testing on other Ivy Bridge ThinkPads.
- Additional output-path diagnostics.

## [1.0.0] — Initial T430BLC release

### BLCSET

- Added command-line LCD brightness control under real MS-DOS.
- Added dynamic Intel graphics BAR0 discovery.
- Added active backlight PWM maximum detection.
- Added duty-value clamping and readback verification.
- Confirmed active T430 brightness registers at `BAR0+48250h`, `BAR0+48254h`, and `BAR0+C8254h`.

### BLCINIT

- Added CONFIG.SYS device driver for one-time brightness initialization.
- Added hexadecimal argument parsing and corrected hexadecimal display output.
- Confirmed successful execution during DOS boot before EMM386.

### Protected-mode framework

- Added temporary protected-mode entry from real DOS.
- Added runtime-patched GDT and flat 4 GiB physical-memory descriptor.
- Added XMS-controlled A20 handling and interrupt/NMI masking.
- Fixed a triple fault caused by writing through a non-writable code selector.
- Added explicit address-size and operand-size encodings required by TASM.
