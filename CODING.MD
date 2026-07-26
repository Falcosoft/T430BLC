# T430LCD Coding and Build Conventions

This document defines the source, build, and repository conventions used by T430LCD.

The project targets real MS-DOS systems and must remain buildable without DOSLFN or other long-filename extensions.

## 1. DOS compatibility

All directories and files used directly by the DOS build process must follow the DOS 8.3 naming convention.

Examples:

```text
TOOLS
DIAG
BRIGHT
ASPECT
INCL
BUILD
BIN
BLCSET.ASM
BUILD.BAT
CLEAN.BAT
MMIO.INC
```

Descriptive Markdown documentation filenames may use long filenames because they are intended primarily for GitHub and web-browser use.

Examples:

```text
ReverseEngineering.md
DevelopmentHistory.md
IntelRegisters.md
KnownLimitations.md
```

## 2. Line endings

All generated and committed text files should use DOS/Windows CRLF line endings:

```text
\r\n
```

This applies especially to:

- `.BAT`
- `.ASM`
- `.INC`
- `.TXT`
- `.CFG`
- `.DEF`
- `.LNK`
- `.MAK`

Markdown files may also use CRLF for repository-wide consistency.

## 3. TASM source directive order

For 16-bit tiny-model programs that use 80386 or privileged instructions, use:

```asm
.model tiny
.386p
.code
```

Do not use:

```asm
.386
.model tiny
.code
```

or:

```asm
.386p
.model tiny
.code
```

The verified order avoids TASM instruction and operand-size errors.

## 4. TLINK command-line options

Use lowercase `/t` when generating `.COM` files:

```dos
TLINK /t PROGRAM.OBJ
```

Do not replace it with uppercase `/T`.

For device-driver builds, retain the verified driver-specific link procedure used by that project.

## 5. DOS-compatible batch syntax

Batch files must be compatible with classic MS-DOS `COMMAND.COM`.

Do not use separate standard-error redirection:

```dos
2>NUL
```

Classic DOS interprets `2` as an extra command parameter.

Use:

```dos
IF EXIST PROGRAM.OBJ DEL PROGRAM.OBJ >NUL
```

instead of:

```dos
DEL PROGRAM.OBJ >NUL 2>NUL
```

Avoid modern CMD.EXE-only syntax unless explicitly documented as requiring Windows.

## 6. Build scripts

Every subproject should contain:

```text
BUILD.BAT
CLEAN.BAT
README.md
```

A typical `.COM` build is:

```dos
TASM /M9 /I..\..\..\INCL PROGRAM.ASM
TLINK /t PROGRAM.OBJ
```

Include paths must remain valid under DOS 8.3 naming rules.

Root-level build scripts must reference only DOS-compatible directory names.

## 7. Shared include files

Only stable and hardware-verified definitions should be moved into shared includes.

Appropriate shared content includes:

- selector constants
- exact MMIO opcode macros
- verified graphics register offsets

Hardware-sensitive logic should remain local to each utility unless a refactor has been compiled and regression-tested on real hardware.

This includes:

- protected-mode entry and exit
- GDT construction
- interrupt hooks
- XMS handling
- register write order
- command parsing
- TSR installation and removal

## 8. Protected-mode conventions

The verified protected-mode layout is:

```text
CS = 16-bit executable code selector
ES = writable program-data selector
DS = flat 4 GiB physical-memory selector
SS = writable program-data selector
```

Rules:

- Access physical MMIO through `DS`.
- Write program variables through `ES`.
- Never write through the protected-mode code selector.
- Disable interrupts and NMI during the transition.
- Restore real-mode segments before DOS or BIOS calls.
- Do not perform the direct CR0/LGDT transition under EMM386 or VM86.

## 9. Explicit MMIO instruction encodings

TASM source files use exact byte encodings for 32-bit MMIO access from 16-bit protected-mode code.

Read DWORD from `DS:[ESI]`:

```asm
db 067h,066h,08Bh,006h
```

Write `EAX` to `DS:[ESI]`:

```asm
db 067h,066h,089h,006h
```

Use the shared MMIO macros where available.

## 10. Hardware-write policy

Change the smallest possible verified register set.

For brightness:

```text
Write the active PWM duty register only.
```

For aspect-ratio correction:

```text
Write PF_A_POS first.
Write PF_A_SIZE second.
```

Do not write:

```text
PF_A_CTL
PF_A_VSCALE
PF_A_HSCALE
```

Rewriting the fitter control register caused flickering and corrupted output during testing.

Every hardware write should be followed by immediate readback verification when practical.

## 11. Diagnostics before writes

New hardware support should begin with a read-only diagnostic.

Recommended process:

1. Read and record the current state.
2. Change one known user-visible condition.
3. Read and compare the state again.
4. Identify the smallest changing register set.
5. Test one controlled write.
6. Verify readback.
7. Validate visible behavior on real hardware.
8. Only then integrate the change into an end-user utility.

Do not combine unknown register writes with an unverified protected-mode transition.

## 12. Hardware support claims

T430LCD should claim support only for hardware verified on a physical machine.

A test report should include:

```text
Computer model:
CPU:
Integrated GPU:
Internal panel resolution:
External connection type:
DOS version:
HIMEM version:
EMM386 loaded:
Utility:
Command:
Exact output:
Visible result:
```

Do not assume that another Ivy Bridge system uses the same fitter, pipe, firmware, or backlight configuration.

## 13. Source formatting

Use clear labels and descriptive comments.

Prefer:

```asm
ApplyAspectFromHook:
ReadFitter:
PrepareProtectedMode:
```

over cryptic one-letter labels except for very small local loops.

Keep hexadecimal hardware values explicit:

```asm
mov eax,00C80000h
```

Preserve the original order of hardware-sensitive operations.

Avoid unnecessary code-style rewrites in the same commit as a functional hardware change.

## 14. Repository changes

Keep pull requests focused.

Preferred categories:

- documentation-only
- build-system-only
- diagnostic-only
- hardware-support change
- refactor with no intended behavior change

A refactor that touches protected-mode or MMIO code must be compiled and regression-tested on the T430 before release.

## 15. Attribution

T430LCD was developed through a collaborative reverse-engineering process between:

- Zoltán Bacskó (Falcosoft): hardware testing, compilation, validation, project maintenance
- OpenAI ChatGPT: implementation generation, debugging analysis, refactoring, and documentation

Contributions should preserve this transparent development history.

## 16. Release acceptance checklist

Before publishing a release:

- all build-time paths are DOS 8.3 compatible
- all text files use CRLF line endings
- all `.COM` projects use `TLINK /t`
- batch files avoid `2>NUL`
- `BUILDALL.BAT` succeeds on real DOS
- `CLEANALL.BAT` succeeds on real DOS
- BLCSET is tested
- BLCINIT is tested
- ASPECT install and `/U` unload are tested
- internal LCD behavior is verified
- external VGA behavior is verified
- external DVI behavior is verified
- documentation matches the released source
