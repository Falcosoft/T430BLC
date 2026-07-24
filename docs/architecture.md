# Architecture

## Shared hardware contract

`COMMON.INC` centralizes selector values, PWM register offsets, and the exact MMIO read/write instruction encodings. The working hardware sequence remains visible in each front end so that its different execution environment is easy to audit.

The two programs intentionally do not share every routine:

- `BLCSET` is an ordinary COM program and may use DOS services for output and termination.
- `BLCINIT` runs while CONFIG.SYS is being processed, uses BIOS teletype output, receives a DOS driver request packet, and must manage a private stack.

Forcing these environment-specific paths into heavily conditional common code would make the critical boot driver harder to verify.

## Protected-mode sequence

Both programs perform the same high-level operation:

1. Read graphics BAR0 through PCI BIOS function `B10Ah`.
2. Obtain the XMS entry point and locally enable A20.
3. Build a small GDT containing 16-bit code, 16-bit writable data, and flat 4 GB data descriptors.
4. Disable interrupts and NMI temporarily.
5. Set CR0.PE and far-jump into protected mode.
6. Use flat `DS` for graphics MMIO and writable `ES` for program variables.
7. Read the maximum, clamp the request, write the duty register, and verify by readback.
8. Clear CR0.PE, far-jump back to real mode, and restore machine state.

## Driver lifetime

`BLCINIT` is a DOS character device. During its initialization request it returns `ResidentEnd` as the break address. DOS therefore discards the parser, PCI/XMS logic, GDT, private stack, protected-mode code, messages, and temporary data after boot.

Only the device header, saved request pointer, strategy routine, and inert interrupt routine remain resident.

## Important correctness details

- Protected-mode variables are written through writable `ES`, never through the executable code selector.
- The driver saves the DOS-provided `SS:SP`, switches to a private stack based in its own segment, and restores the original stack after returning to real mode.
- The driver reloads the saved request-packet pointer after printing because BIOS output routines use `BX`.
- `PrintNibble` preserves `BX`; otherwise BIOS color value `07h` corrupts the byte retained in `BL` by `PrintHex8`.
