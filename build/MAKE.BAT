@echo off
rem Build T430BLC with Borland TASM, TLINK and EXE2BIN.
rem Run this batch file from the BUILD directory.

if not exist ..\bin mkdir ..\bin

copy ..\src\COMMON.INC . >nul
copy ..\src\BLCSET.ASM . >nul
copy ..\src\BLCINIT.ASM . >nul

TASM /m9 BLCSET.ASM
if errorlevel 1 goto error
TLINK /t BLCSET.OBJ
if errorlevel 1 goto error
copy /y BLCSET.COM ..\bin\BLCSET.COM >nul

TASM /m9 BLCINIT.ASM
if errorlevel 1 goto error
TLINK /x BLCINIT.OBJ,BLCINIT.EXE
if errorlevel 1 goto error
EXE2BIN BLCINIT.EXE BLCINIT.SYS
if errorlevel 1 goto error
copy /y BLCINIT.SYS ..\bin\BLCINIT.SYS >nul

echo.
echo Build complete. Output is in ..\bin

del COMMON.INC BLCSET.ASM BLCINIT.ASM >nul 2>nul
goto end

:error
echo.
echo Build failed.

:end
