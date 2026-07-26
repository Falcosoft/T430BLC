# Design Notes

## Philosophy

T430LCD intentionally follows a conservative engineering philosophy:

- Measure before modifying.
- Prefer read-only diagnostics first.
- Change the smallest possible register set.
- Verify every hardware write by readback and visible behaviour.
- Generalize only after confirming behaviour on real hardware.

## Brightness design

Only the active PWM duty register is written. The maximum duty cycle is detected
from hardware instead of being hard-coded. Requested values are clamped.

## ASPECT design

The final algorithm is based on observed display-engine behaviour rather than
connector type.

At installation:

1. Read the current panel-fitter destination.
2. If it is already 4:3, do not install.
3. Otherwise compute the largest centred 4:3 rectangle.

After each watched mode change:

1. Skip native VESA modes.
2. Read the current fitter destination.
3. Apply the correction only if the BIOS restored the same fixed-raster
   destination captured during installation.

This avoids disturbing external outputs that already generate correct timings.

## Protected-mode framework

The utilities use a temporary protected-mode transition because graphics MMIO
resides near F0000000h. The framework:

- enables A20 through XMS
- installs a runtime GDT
- enters 16-bit protected mode
- uses a flat 4 GiB data selector
- restores real mode immediately after the operation

The framework is reused by multiple utilities.

## Why PF_A_CTL is never written

Experiments showed that rewriting PF_A_CTL could produce flickering or corrupted
output even when writing back the same value. Stable operation required changing
only PF_A_POS followed by PF_A_SIZE.

## Future direction

A DPMI-based implementation is planned for EMM386 compatibility. The expected
architecture uses:

- DPMI physical-memory mapping
- a protected-mode service
- a real-mode callback from the INT 10h hook

VCPI is intentionally not the preferred direction because compatibility with
VSBHDA is an explicit project goal.
