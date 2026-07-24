# Building and installation

## Requirements

The source uses Borland TASM syntax and 80386 protected-mode instructions.

- TASM
- TLINK
- EXE2BIN
- A real DOS environment for execution

## Automated build

Change to the `build` directory and run:

```dos
MAKE.BAT
```

The resulting files are copied to `bin`.

## Manual build: BLCSET

```dos
TASM /m9 BLCSET.ASM
TLINK /t BLCSET.OBJ
```

`/t` is correct for BLCSET because it is a COM program whose entry point is at offset `0100h`.

## Manual build: BLCINIT

```dos
TASM /m9 BLCINIT.ASM
TLINK /x BLCINIT.OBJ,BLCINIT.EXE
EXE2BIN BLCINIT.EXE BLCINIT.SYS
```

Do **not** use `TLINK /t` for BLCINIT. A COM image requires an initial entry point at offset `0100h`, while a DOS device driver is a raw binary whose device header begins at file offset `0000h`.

## BLCINIT installation

Place the driver on the DOS boot volume and load it after HIMEM.SYS but before EMM386:

```ini
DEVICE=C:\DOS\HIMEM.SYS
DEVICE=C:\DOS\BLCINIT.SYS 01E7
DEVICE=C:\DOS\EMM386.EXE RAM
DOS=HIGH,UMB
```

The argument must contain one to four hexadecimal digits.

## First boot precautions

Use a CONFIG.SYS startup menu, the DOS bypass key, or a recovery disk for the first test on any machine other than the verified T430.
