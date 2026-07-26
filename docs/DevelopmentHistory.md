# Development History

## Phase 1 – Brightness

The project started from a practical request: restore the preferred LCD
brightness automatically after booting DOS.

This led to:

- PCI discovery
- MMIO discovery
- protected-mode framework
- BLCSET
- BLCINIT

## Phase 2 – Panel fitting

The next goal was preventing stretched 4:3 graphics on the internal LCD.

Important milestones included:

- FITREAD
- PFDIAG
- PFSET
- ASPECT
- PFSNAP

Repeated experiments on internal LCD, analog VGA and digital DVI revealed that
the correct decision criterion is whether the BIOS restores a fixed-raster
destination rather than the connector type.

## Phase 3 – Documentation

The repository evolved from T430BLC into T430LCD, adding structured user,
developer and reverse-engineering documentation together with an MIT license and
public development history.

## Future

- DPMI / EMM386 support
- additional Ivy Bridge hardware validation
- community testing and contributions
