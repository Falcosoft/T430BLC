# T430BLC

**LCD brightness control utilities for the Lenovo ThinkPad T430 under real MS-DOS.**

T430BLC controls the internal LCD backlight by programming the Intel Ivy Bridge / HD Graphics 4000 PWM registers directly. It provides both an interactive command-line utility and a boot-time CONFIG.SYS device driver.

## Programs

### BLCSET.COM

Sets the brightness from the DOS command line:

```dos
BLCSET 01E7
```

The argument is a hexadecimal PWM duty value from `0000` through the detected hardware maximum. On the development T430, representative values were:

| Value | Approximate level |
|---:|---|
| `0045` | Low |
| `01E7` | Medium |
| `1155` | Maximum |

### BLCINIT.SYS

Sets a fixed brightness once during CONFIG.SYS processing, before EMM386 is installed:

```ini
DEVICE=C:\DOS\HIMEM.SYS
DEVICE=C:\DOS\BLCINIT.SYS 01E7
DEVICE=C:\DOS\EMM386.EXE RAM
DOS=HIGH,UMB
```

This avoids repeated Fn+F8 presses at every DOS boot. After initialization, DOS discards nearly all of the driver's setup and protected-mode code; only a minimal character-device header and inert request handler remain resident.

## Verified hardware

- Lenovo ThinkPad T430
- Intel Core i7-3632QM
- Intel HD Graphics 4000
- Graphics PCI function `00:02.0`
- Real MS-DOS with HIMEM.SYS and EMM386

Other Ivy Bridge systems may use the same registers, but they have not been tested by this project.

## Register path

| MMIO register | Purpose |
|---|---|
| `BAR0 + 48250h` | CPU PWM control/enable |
| `BAR0 + 48254h` | Current PWM duty in the low 16 bits |
| `BAR0 + C8254h` | Maximum PWM duty in the upper 16 bits |

Only `BAR0 + 48254h` is written. Its upper 16 bits are preserved, and the requested duty is clamped to the detected maximum.

## Building

Required tools:

- Borland Turbo Assembler (TASM)
- Borland TLINK
- EXE2BIN

From the `build` directory:

```dos
MAKE.BAT
```

Manual commands are documented in [docs/building.md](docs/building.md).

## Safety

This software writes directly to chipset graphics MMIO registers and performs a temporary protected-mode transition. It is hardware-specific. Keep a CONFIG.SYS bypass or recovery boot disk available when testing on a new system.

## Documentation

- [Architecture](docs/architecture.md)
- [Building and installation](docs/building.md)
- [Hardware and registers](docs/hardware.md)
- [Reverse-engineering history](docs/reverse_engineering.md)
- [Development and attribution](docs/development_history.md)
- [Publishing on GitHub](docs/github_publication.md)

## Development and attribution

This project was developed through an interactive collaboration:

- **Zoltán Bacskó:** problem definition, hardware investigation, compilation, testing on physical hardware, validation, and project maintenance.
- **OpenAI ChatGPT (GPT-5.6 Thinking):** software implementation, debugging analysis, source-code generation, refactoring, and documentation drafting.

The code did not emerge as a one-shot generation. It was refined through repeated experiments on a real ThinkPad T430. See [docs/development_history.md](docs/development_history.md) for details.

## License

Released under the MIT License. See [LICENSE](LICENSE).
