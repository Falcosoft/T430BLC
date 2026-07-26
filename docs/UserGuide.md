# T430LCD User Guide

## 1. Introduction

T430LCD addresses two practical Lenovo ThinkPad T430 problems under real MS-DOS:

1. restoring a preferred LCD brightness automatically at boot
2. preventing legacy 4:3 DOS modes from being stretched across the internal widescreen LCD

The utilities communicate directly with Intel HD Graphics 4000 hardware and are verified on physical T430 hardware.

## 2. Requirements

### Verified hardware

- Lenovo ThinkPad T430
- Intel HD Graphics 4000
- internal 1600×900 LCD
- external analog VGA output
- external digital/DVI output

### Software

Required:

- real MS-DOS
- HIMEM/XMS
- Borland TASM/TLINK only when building from source

Not currently supported:

- EMM386 runtime operation
- Windows DOS boxes or NTVDM
- emulators without compatible physical Intel hardware access

Recommended baseline:

```ini
DEVICE=C:\DOS\HIMEM.SYS
DOS=HIGH
```

## 3. Installation layout

```text
C:\T430LCD\
    BLCSET.COM
    BLCINIT.SYS
    ASPECT.COM
```

Diagnostics may be kept in:

```text
C:\T430LCD\DIAG\
    FITREAD.COM
    PFDIAG.COM
    PFSNAP.COM
```

## 4. BLCSET

### Syntax

```dos
BLCSET hexadecimal-value
```

Example:

```dos
BLCSET 0800
```

The value is hexadecimal. The tested hardware reported a maximum of `1155h`.

Example values:

```dos
BLCSET 0040
BLCSET 0400
BLCSET 0800
BLCSET 1155
```

BLCSET locates Intel BAR0, detects the maximum PWM value, clamps the request, writes the active duty register, and verifies the readback.

## 5. BLCINIT

### CONFIG.SYS syntax

```ini
DEVICE=C:\T430LCD\BLCINIT.SYS hexadecimal-value
```

Example:

```ini
DEVICE=C:\DOS\HIMEM.SYS
DEVICE=C:\T430LCD\BLCINIT.SYS 0800
```

BLCINIT sets brightness once during boot and then finishes initialization. It avoids repeatedly pressing the ThinkPad brightness hotkey, which may conflict with application shortcuts such as Norton Commander file-order controls.

## 6. ASPECT

### Install

```dos
ASPECT
```

### Unload

```dos
ASPECT /U
```

ASPECT unloads only when it is still the newest handler on both `INT 10h` and `INT 2Fh`. If another TSR hooked either interrupt afterward, ASPECT refuses to unload to avoid breaking the chain.

### AUTOEXEC.BAT example

```bat
@ECHO OFF
C:\T430LCD\ASPECT.COM
PATH C:\DOS;C:\UTIL
```

### Internal LCD

On the verified 1600×900 panel:

```text
native fitter destination: 1600×900
calculated 4:3 window:      1200×900
position:                   200,0
```

### External analog VGA

The BIOS generates mode-specific output timings, for example 720×400 text and 640×480 for mode 13h. ASPECT detects the changing destination and leaves it unchanged.

### External DVI

The tested DVI path already uses a 640×480 destination for legacy graphics modes. Since this is 4:3, ASPECT does not install a correction hook.

### Native VESA modes

A VESA mode matching the detected output dimensions remains full-screen.

### Mode changes watched

```text
INT 10h AH=00h
INT 10h AX=4F02h
```

### Decision logic

At installation:

```text
read PF_A_SIZE

if destination is 4:3:
    do not install
else:
    save widescreen destination
    calculate centered 4:3 window
    install TSR
```

After each watched mode change:

```text
if native VESA mode:
    do nothing
else if current PF_A_SIZE equals saved widescreen size:
    apply the calculated 4:3 window
else:
    leave BIOS programming untouched
```

## 7. Memory managers

### HIMEM

HIMEM/XMS is required for A20 control.

### EMM386

The current direct protected-mode transition cannot run from EMM386 virtual-8086 mode. Do not run current BLCSET or ASPECT builds under EMM386.

### Planned DPMI implementation

The planned approach is to detect a DPMI host, map the required graphics MMIO page, allocate a real-mode callback, and keep a protected-mode service resident. DPMI is preferred over VCPI for compatibility with VSBHDA.

## 8. Diagnostics

### FITREAD

Reads Intel OpRegion panel-fitting fields.

### PFDIAG

Reads all three Ivy Bridge panel-fitter blocks.

### PFSNAP

Install:

```dos
PFSNAP /I
```

Clear:

```dos
PFSNAP /C
```

Run a graphics program, return to DOS, then dump:

```dos
PFSNAP /D
```

PFSNAP records requested BIOS modes, before/after state, fitter A/B/C registers, pipe timing registers, source sizes, and skipped VM86 captures.

## 9. Troubleshooting

### Immediate reboot

Possible causes include an obsolete experimental build, EMM386 being active, unsupported hardware, or an unsafe protected-mode transition. Use only the verified final sources and boot without EMM386.

### ASPECT reports that output is already 4:3

This is expected for external outputs where the BIOS already generates a correct legacy timing. No correction TSR is needed.

### External display becomes garbled

Use only the conservative ASPECT build. Older builds applied startup-derived window sizes unconditionally and could corrupt mode-dependent external outputs.

### ASPECT /U refuses to unload

Another TSR owns `INT 10h` or `INT 2Fh` after ASPECT. Unload the later TSR first or reboot.

### XMS MMIO test returns repeatable garbage

XMS function `0Bh` handle-zero offsets are packed real-mode far pointers, not arbitrary 32-bit physical addresses. This mechanism cannot access MMIO near `F0000000h`.

## 10. Tested software

Confirmed during development:

- MS-DOS text mode
- standard VGA programs
- Duke Nukem 3D
- Descent
- Norton Commander coexistence with boot-time brightness initialization

## 11. Reporting results

Include:

```text
Computer model:
CPU:
Integrated GPU:
Internal panel resolution:
Connection type:
DOS version:
HIMEM version:
EMM386 loaded:
Utility and command:
Exact output:
Visible result:
```

For diagnostic reports, include complete output rather than selected lines.

## 12. License and attribution

T430LCD is licensed under the MIT License.

Zoltán Bacskó performed hardware investigation, compilation, testing, validation, and maintenance. OpenAI ChatGPT generated and refined implementation code, debugging analysis, refactoring, and documentation. Every supported hardware behavior was validated on physical Lenovo ThinkPad T430 hardware.
