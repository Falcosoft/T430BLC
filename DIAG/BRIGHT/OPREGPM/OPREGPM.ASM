; OPREGPM.ASM
; Lenovo ThinkPad T430 / Intel HD Graphics 4000
; Read-only Intel Graphics OpRegion diagnostic using a brief 386 protected-mode copy.
;
; 16-bit DOS .COM, TASM syntax, 80386+.
;
; Build:
;   TASM /m9 OPREGPM.ASM
;   TLINK /t OPREGPM.OBJ
;
; SAFETY:
;   - PCI BIOS configuration READ only
;   - reads 0400h bytes from the physical address in PCI ASLS
;   - no PCI writes
;   - no EC access
;   - no graphics MMIO writes
;   - no OpRegion writes
;   - no brightness changes
;
; IMPORTANT:
;   This program briefly enters protected mode with interrupts and NMI disabled.
;   It has not been physically tested on a T430 by the author.

.model tiny
.386p
.code
org 100h

SEL_CODE16  equ 08h
SEL_DATA16  equ 10h
SEL_FLAT    equ 18h

start:
        mov     ax, cs
        mov     ds, ax
        mov     es, ax

        mov     dx, offset MsgTitle
        call    PrintZ

        ; Read live Intel ASLS from PCI 00:02.0 offset FCh.
        mov     di, 0FCh
        call    PciReadDword
        jc      PciReadFailed
        mov     dword ptr [Asls], ecx

        mov     dx, offset MsgAsls
        call    PrintZ
        mov     eax, dword ptr [Asls]
        call    PrintHex32
        call    PrintCRLF

        test    eax, eax
        jz      AslsInvalid

        ; Locate XMS manager, used only for A20 control.
        mov     ax, 4300h
        int     2Fh
        cmp     al, 80h
        jne     XmsNotPresent

        mov     ax, 4310h
        int     2Fh
        mov     word ptr [XmsEntry], bx
        mov     word ptr [XmsEntry+2], es

        push    ds
        pop     es

        ; Locally enable A20 through XMS.
        mov     ah, 05h
        call    dword ptr cs:[XmsEntry]
        or      ax, ax
        jz      A20EnableFailed
        mov     byte ptr [A20EnabledByUs], 1

        ; Construct runtime GDT bases and far-return segment.
        call    PrepareProtectedMode

        mov     dx, offset MsgCopyStart
        call    PrintZ

        ; Save flags, disable maskable interrupts.
        pushf
        pop     word ptr [SavedFlags]
        cli

        ; Disable NMI while no protected-mode IDT is installed.
        in      al, 70h
        mov     byte ptr [SavedPort70], al
        or      al, 80h
        out     70h, al

        lgdt    fword ptr [Gdtr]

        ; Enter protected mode.
        mov     eax, cr0
        or      al, 01h
        mov     cr0, eax

        ; Flush prefetch queue and load protected-mode CS.
ProtectedModeJump:
        db      0EAh
ProtectedModeJumpOffset:
        dw      offset CorrectProtectedEntry
        dw      SEL_CODE16

; Protected-mode copy routine.
CorrectProtectedEntry:
        ; Program-relative stack selector.
        mov     ax, SEL_DATA16
        mov     ss, ax

        ; Flat source and destination selectors.
        mov     ax, SEL_FLAT
        mov     ds, ax
        mov     es, ax

        mov     esi, dword ptr cs:[Asls]
        mov     edi, dword ptr cs:[BufferLinear]
        mov     ecx, 100h
        cld

        ; 16-bit code segment requires BOTH overrides:
        ;   67h = 32-bit address size, so MOVS uses ESI/EDI
        ;   66h = 32-bit operand size, so MOVS copies DWORDs
        ; TASM's plain REP MOVSD emits only the operand-size override here
        ; and therefore uses SI/DI, which incorrectly copies from the COM image.
        db      0F3h, 067h, 066h, 0A5h       ; rep a32 movsd

        ; Restore program-relative selectors.
        mov     ax, SEL_DATA16
        mov     ds, ax
        mov     es, ax
        mov     ss, ax

        mov     eax, cr0
        and     al, 0FEh
        mov     cr0, eax

        db      0EAh
        dw      offset RealModeReturn
        dw      0000h                ; patched at runtime

CorrectReturnSegment equ ($-2)

RealModeReturn:
        mov     ax, cs
        mov     ds, ax
        mov     es, ax
        mov     ss, ax

        ; Restore NMI state and original FLAGS before calling DOS.
        mov     al, byte ptr [SavedPort70]
        out     70h, al
        push    word ptr [SavedFlags]
        popf

        ; Validate the 16-byte Intel OpRegion signature.
        mov     si, offset OpRegionBuffer
        mov     di, offset ExpectedSignature
        mov     cx, 16
        repe    cmpsb
        jne     SignatureBad

        mov     dx, offset MsgSignatureOK
        call    PrintZ

        mov     dx, offset MsgSignature
        call    PrintZ
        mov     si, offset OpRegionBuffer
        mov     cx, 16
PrintSignatureLoop:
        lodsb
        mov     dl, al
        call    PutCh
        loop    PrintSignatureLoop
        call    PrintCRLF

        mov     dx, offset MsgHeader
        call    PrintZ

        mov     dx, offset Label00
        call    PrintZ
        mov     eax, dword ptr [OpRegionBuffer+000h]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset Label10
        call    PrintZ
        mov     eax, dword ptr [OpRegionBuffer+010h]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset Label14
        call    PrintZ
        mov     eax, dword ptr [OpRegionBuffer+014h]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset Label18
        call    PrintZ
        mov     eax, dword ptr [OpRegionBuffer+018h]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset Label1C
        call    PrintZ
        mov     eax, dword ptr [OpRegionBuffer+01Ch]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset MsgAsle
        call    PrintZ

        mov     dx, offset Label300
        call    PrintZ
        mov     eax, dword ptr [OpRegionBuffer+300h]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset Label304
        call    PrintZ
        mov     eax, dword ptr [OpRegionBuffer+304h]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset Label308
        call    PrintZ
        mov     eax, dword ptr [OpRegionBuffer+308h]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset Label310
        call    PrintZ
        mov     eax, dword ptr [OpRegionBuffer+310h]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset Label330
        call    PrintZ
        mov     eax, dword ptr [OpRegionBuffer+330h]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset MsgDone
        call    PrintZ
        call    DisableA20IfNeeded
        mov     ax, 4C00h
        int     21h

; Build descriptor bases and linear buffer address.
PrepareProtectedMode proc near
        push    ax
        push    bx
        push    dx
        push    eax

        ; EAX = program physical/linear base = CS << 4.
        xor     eax, eax
        mov     ax, cs
        shl     eax, 4
        mov     dword ptr [ProgramLinear], eax

        ; Patch CODE16 and DATA16 descriptor bases.
        mov     bx, offset GdtCode16
        call    SetDescriptorBase
        mov     bx, offset GdtData16
        call    SetDescriptorBase

        ; GDTR base = program linear + offset GdtStart.
        mov     edx, eax
        xor     eax, eax
        mov     ax, offset GdtStart
        add     eax, edx
        mov     dword ptr [Gdtr+2], eax

        ; Conventional destination linear address.
        mov     eax, edx
        xor     edx, edx
        mov     dx, offset OpRegionBuffer
        add     eax, edx
        mov     dword ptr [BufferLinear], eax

        ; Patch the real-mode far-jump segment word.
        mov     ax, cs
        mov     word ptr cs:[CorrectReturnSegment], ax

        ; Entry jump already targets CorrectProtectedEntry.

        pop     eax
        pop     dx
        pop     bx
        pop     ax
        ret
PrepareProtectedMode endp

; BX -> descriptor, EAX = 32-bit base.
SetDescriptorBase proc near
        mov     word ptr [bx+2], ax
        ror     eax, 16
        mov     byte ptr [bx+4], al
        mov     byte ptr [bx+7], ah
        ror     eax, 16
        ret
SetDescriptorBase endp

DisableA20IfNeeded proc near
        cmp     byte ptr [A20EnabledByUs], 0
        je      DisableA20Done
        mov     ah, 06h
        call    dword ptr cs:[XmsEntry]
        mov     byte ptr [A20EnabledByUs], 0
DisableA20Done:
        ret
DisableA20IfNeeded endp

PciReadFailed:
        mov     dx, offset MsgPciFail
        call    PrintZ
        jmp     ExitError

AslsInvalid:
        mov     dx, offset MsgAslsInvalid
        call    PrintZ
        jmp     ExitError

XmsNotPresent:
        mov     dx, offset MsgNoXms
        call    PrintZ
        jmp     ExitError

A20EnableFailed:
        mov     byte ptr [XmsError], bl
        mov     dx, offset MsgA20Fail
        call    PrintZ
        mov     al, byte ptr [XmsError]
        call    PrintHex8
        call    PrintCRLF
        jmp     ExitError

SignatureBad:
        mov     dx, offset MsgSignatureBad
        call    PrintZ
        mov     dx, offset MsgActual
        call    PrintZ
        mov     si, offset OpRegionBuffer
        mov     cx, 16
BadSigLoop:
        lodsb
        call    PrintHex8
        mov     dl, ' '
        call    PutCh
        loop    BadSigLoop
        call    PrintCRLF
        call    DisableA20IfNeeded
        mov     ax, 4C01h
        int     21h

ExitError:
        call    DisableA20IfNeeded
        mov     ax, 4C01h
        int     21h

PciReadDword proc near
        mov     ax, 0B10Ah
        xor     bh, bh
        mov     bl, 10h
        int     1Ah
        ret
PciReadDword endp

PrintCRLF proc near
        mov     dx, offset MsgCRLF
        call    PrintZ
        ret
PrintCRLF endp

PrintZ proc near
        push    ax
        push    si
        mov     si, dx
PZLoop:
        lodsb
        or      al, al
        jz      PZDone
        mov     dl, al
        call    PutCh
        jmp     PZLoop
PZDone:
        pop     si
        pop     ax
        ret
PrintZ endp

PutCh proc near
        push    ax
        mov     ah, 02h
        int     21h
        pop     ax
        ret
PutCh endp

PrintHex32 proc near
        push    eax
        ror     eax, 16
        call    PrintHex16
        ror     eax, 16
        call    PrintHex16
        pop     eax
        ret
PrintHex32 endp

PrintHex16 proc near
        push    ax
        mov     al, ah
        call    PrintHex8
        pop     ax
        call    PrintHex8
        ret
PrintHex16 endp

PrintHex8 proc near
        push    ax
        push    bx
        mov     bl, al
        mov     al, bl
        shr     al, 4
        call    PrintNibble
        mov     al, bl
        and     al, 0Fh
        call    PrintNibble
        pop     bx
        pop     ax
        ret
PrintHex8 endp

PrintNibble proc near
        and     al, 0Fh
        cmp     al, 9
        jbe     NibbleDigit
        add     al, 'A'-10
        jmp     short NibbleOut
NibbleDigit:
        add     al, '0'
NibbleOut:
        mov     dl, al
        call    PutCh
        ret
PrintNibble endp

; ------------------------- GDT -------------------------
; No alignment directive is required for LGDT.
GdtStart:
GdtNull:
        dq 0

; 16-bit code descriptor, base patched at runtime, limit FFFFh.
GdtCode16:
        dw 0FFFFh
        dw 0000h
        db 00h
        db 09Ah
        db 00h
        db 00h

; 16-bit writable data descriptor, base patched at runtime, limit FFFFh.
GdtData16:
        dw 0FFFFh
        dw 0000h
        db 00h
        db 092h
        db 00h
        db 00h

; Flat writable data descriptor, base 0, limit 4 GiB.
GdtFlat:
        dw 0FFFFh
        dw 0000h
        db 00h
        db 092h
        db 0CFh
        db 00h
GdtEnd:

Gdtr:
        dw GdtEnd-GdtStart-1
        dd 0

MsgTitle:
        db 13,10,'OPREGPM - T430 Intel OpRegion Protected-Mode Diagnostic',13,10
        db 'READ-ONLY: PCI read and physical-memory copy only.',13,10,0
MsgAsls:
        db 'PCI ASLS (00:02.0/FCh): ',0
MsgCopyStart:
        db 'Entering protected mode for a 0400h-byte read...',13,10,0
MsgSignatureOK:
        db 'OpRegion signature is valid.',13,10,0
MsgSignature:
        db 'Signature: ',0
MsgHeader:
        db 13,10,'Selected OpRegion header DWORDs:',13,10,0
MsgAsle:
        db 13,10,'ASLE mailbox / T430 DSDT fields:',13,10,0
MsgDone:
        db 13,10,'Read-only protected-mode diagnostic complete.',13,10,0

MsgPciFail:
        db 'PCI BIOS read of ASLS failed.',13,10,0
MsgAslsInvalid:
        db 'ASLS is zero; refusing physical-memory access.',13,10,0
MsgNoXms:
        db 'No XMS manager detected; A20 was not changed.',13,10,0
MsgA20Fail:
        db 'XMS could not enable A20; error BL=',0
MsgSignatureBad:
        db 'Unexpected OpRegion signature; no writes attempted.',13,10,0
MsgActual:
        db 'First 16 bytes: ',0
MsgCRLF:
        db 13,10,0

Label00 db '  +000h: ',0
Label10 db '  +010h: ',0
Label14 db '  +014h: ',0
Label18 db '  +018h: ',0
Label1C db '  +01Ch: ',0
Label300 db '  ARDY +300h: ',0
Label304 db '  ASLC +304h: ',0
Label308 db '  TCHE +308h: ',0
Label310 db '  BCLP +310h: ',0
Label330 db '  PFMB +330h: ',0

ExpectedSignature db 'IntelGraphicsMem'

Asls            dd 0
ProgramLinear   dd 0
BufferLinear    dd 0
XmsEntry        dd 0
SavedFlags      dw 0
SavedPort70     db 0
A20EnabledByUs  db 0
XmsError        db 0

OpRegionBuffer  db 400h dup (0)

end start
