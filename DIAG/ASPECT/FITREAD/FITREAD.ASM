; FITREAD.ASM
; Lenovo ThinkPad T430 / Intel HD Graphics 4000
; READ-ONLY Intel OpRegion panel-fitting diagnostic for real MS-DOS.
;
; This utility uses the exact protected-mode entry/exit architecture proven
; by BLCSET/BLCINIT:
;   - HIMEM/XMS A20 control
;   - runtime-patched 16-bit code/data descriptors
;   - flat 4 GB DS for physical-memory reads
;   - writable ES for program variables
;   - no writes through CS in protected mode
;   - NMI and interrupts disabled during the transition
;
; BUILD:
;   TASM /m9 FITREAD.ASM
;   TLINK /t FITREAD.OBJ
;
; RUN:
;   FITREAD
;
; READ-ONLY:
;   No PCI configuration writes
;   No OpRegion writes
;   No graphics MMIO writes

.model tiny
.386p
.code
org 100h

include T430LCD.INC

OPREG_ARDY equ 0300h
OPREG_ASLC equ 0304h
OPREG_TCHE equ 0308h
OPREG_PFIT equ 0314h
OPREG_CPFM equ 0340h
OPREG_EPFM equ 0344h

start:
        mov     ax, cs
        mov     ds, ax
        mov     es, ax

        mov     dx, offset MsgTitle
        call    PrintZ

        ; Read Intel graphics ASLS from PCI 00:02.0 offset FCh.
        mov     di, 0FCh
        call    PciReadDword
        jc      PciReadFailed

        ; ASLS on this T430 is DAF55018h. Do not page-align it:
        ; the low bits are part of the actual OpRegion physical address.
        mov     eax, ecx
        mov     dword ptr [OpRegionBase], eax

        mov     dx, offset MsgAsls
        call    PrintZ
        call    PrintHex32
        call    PrintCRLF

        test    eax, eax
        jz      AslsInvalid

        ; Use XMS only to enable A20.
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

        mov     ah, 05h
        call    dword ptr cs:[XmsEntry]
        or      ax, ax
        jz      A20EnableFailed
        mov     byte ptr [A20EnabledByUs], 1

        call    PrepareProtectedMode

        mov     dx, offset MsgEnter
        call    PrintZ

        pushf
        pop     word ptr [SavedFlags]
        cli

        in      al, 70h
        mov     byte ptr [SavedPort70], al
        or      al, 80h
        out     70h, al

        lgdt    fword ptr [Gdtr]

        mov     eax, cr0
        or      al, 01h
        mov     cr0, eax

        db      0EAh
        dw      offset ProtectedEntry
        dw      SEL_CODE16

ProtectedEntry:
        mov     ax, SEL_DATA16
        mov     ss, ax
        mov     es, ax

        mov     ax, SEL_FLAT
        mov     ds, ax

        mov     byte ptr es:[Checkpoint], 1

        ; Read first 16 bytes of OpRegion signature.
        mov     esi, dword ptr es:[OpRegionBase]
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[Signature0], eax

        add     esi, 4
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[Signature4], eax

        add     esi, 4
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[Signature8], eax

        add     esi, 4
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[SignatureC], eax
        mov     byte ptr es:[Checkpoint], 2

        ; Read ASLE mailbox fields.
        mov     esi, dword ptr es:[OpRegionBase]
        add     esi, OPREG_ARDY
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[Ardy], eax

        mov     esi, dword ptr es:[OpRegionBase]
        add     esi, OPREG_ASLC
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[Aslc], eax

        mov     esi, dword ptr es:[OpRegionBase]
        add     esi, OPREG_TCHE
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[Tche], eax

        mov     esi, dword ptr es:[OpRegionBase]
        add     esi, OPREG_PFIT
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[Pfit], eax

        mov     esi, dword ptr es:[OpRegionBase]
        add     esi, OPREG_CPFM
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[Cpfm], eax

        mov     esi, dword ptr es:[OpRegionBase]
        add     esi, OPREG_EPFM
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[Epfm], eax

        mov     byte ptr es:[Checkpoint], 3
        mov     byte ptr es:[PmStatus], 0

PmReturn:
        mov     ax, SEL_DATA16
        mov     ds, ax
        mov     es, ax
        mov     ss, ax

        mov     eax, cr0
        and     al, 0FEh
        mov     cr0, eax

        db      0EAh
        dw      offset RealModeReturn
        dw      0000h
ReturnSegment equ ($-2)

RealModeReturn:
        mov     ax, cs
        mov     ds, ax
        mov     es, ax
        mov     ss, ax

        mov     al, byte ptr [SavedPort70]
        out     70h, al
        push    word ptr [SavedFlags]
        popf

        mov     dx, offset MsgReturned
        call    PrintZ

        mov     dx, offset MsgCheckpoint
        call    PrintZ
        mov     al, byte ptr [Checkpoint]
        call    PrintHex8
        call    PrintCRLF

        mov     dx, offset MsgSignature
        call    PrintZ
        mov     si, offset Signature0
        mov     cx, 16
PrintSignatureLoop:
        mov     dl, byte ptr [si]
        call    PutCh
        inc     si
        loop    PrintSignatureLoop
        call    PrintCRLF

        mov     dx, offset MsgArdy
        call    PrintZ
        mov     eax, dword ptr [Ardy]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset MsgAslc
        call    PrintZ
        mov     eax, dword ptr [Aslc]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset MsgTche
        call    PrintZ
        mov     eax, dword ptr [Tche]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset MsgPfit
        call    PrintZ
        mov     eax, dword ptr [Pfit]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset MsgCpfm
        call    PrintZ
        mov     eax, dword ptr [Cpfm]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset MsgEpfm
        call    PrintZ
        mov     eax, dword ptr [Epfm]
        call    PrintHex32
        call    PrintCRLF

        mov     eax, dword ptr [Tche]
        test    eax, 4
        jz      NoPanelFitCapability
        mov     dx, offset MsgCapabilityYes
        call    PrintZ
        jmp     short Finish

NoPanelFitCapability:
        mov     dx, offset MsgCapabilityNo
        call    PrintZ

Finish:
        call    DisableA20IfNeeded
        mov     ax, 4C00h
        int     21h

PrepareProtectedMode proc near
        push    ax
        push    bx
        push    dx
        push    eax

        xor     eax, eax
        mov     ax, cs
        shl     eax, 4

        mov     bx, offset GdtCode16
        call    SetDescriptorBase
        mov     bx, offset GdtData16
        call    SetDescriptorBase

        mov     edx, eax
        xor     eax, eax
        mov     ax, offset GdtStart
        add     eax, edx
        mov     dword ptr [Gdtr+2], eax

        mov     ax, cs
        mov     word ptr cs:[ReturnSegment], ax

        pop     eax
        pop     dx
        pop     bx
        pop     ax
        ret
PrepareProtectedMode endp

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
        je      A20Done
        mov     ah, 06h
        call    dword ptr cs:[XmsEntry]
        mov     byte ptr [A20EnabledByUs], 0
A20Done:
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

GdtStart:
        dq 0
GdtCode16:
        dw 0FFFFh, 0000h
        db 00h, 09Ah, 00h, 00h
GdtData16:
        dw 0FFFFh, 0000h
        db 00h, 092h, 00h, 00h
GdtFlat:
        dw 0FFFFh, 0000h
        db 00h, 092h, 0CFh, 00h
GdtEnd:

Gdtr:
        dw GdtEnd-GdtStart-1
        dd 0

OpRegionBase   dd 0
Signature0     dd 0
Signature4     dd 0
Signature8     dd 0
SignatureC     dd 0
Ardy           dd 0
Aslc           dd 0
Tche           dd 0
Pfit           dd 0
Cpfm           dd 0
Epfm           dd 0
XmsEntry       dd 0
SavedFlags     dw 0
SavedPort70    db 0
A20EnabledByUs db 0
XmsError       db 0
Checkpoint     db 0
PmStatus       db 0FFh

MsgTitle:
        db 13,10,'FITREAD - T430 Intel panel-fitting diagnostic',13,10
        db 'READ-ONLY: no PCI, OpRegion, or graphics MMIO writes.',13,10,0
MsgAsls:
        db 'Intel OpRegion ASLS: ',0
MsgEnter:
        db 'Entering protected mode...',13,10,0
MsgReturned:
        db 'Returned from protected mode.',13,10,0
MsgCheckpoint:
        db 'Final checkpoint: ',0
MsgSignature:
        db 'Signature: ',0
MsgArdy:
        db 'ARDY +300h: ',0
MsgAslc:
        db 'ASLC +304h: ',0
MsgTche:
        db 'TCHE +308h: ',0
MsgPfit:
        db 'PFIT +314h: ',0
MsgCpfm:
        db 'CPFM +340h: ',0
MsgEpfm:
        db 'EPFM +344h: ',0
MsgCapabilityYes:
        db 'TCHE panel-fitting capability bit is set.',13,10,0
MsgCapabilityNo:
        db 'TCHE panel-fitting capability bit is NOT set.',13,10,0
MsgPciFail:
        db 'PCI BIOS read of ASLS failed.',13,10,0
MsgAslsInvalid:
        db 'ASLS is zero or invalid.',13,10,0
MsgNoXms:
        db 'HIMEM/XMS is unavailable.',13,10,0
MsgA20Fail:
        db 'XMS could not enable A20; error BL=',0
MsgCRLF:
        db 13,10,0

end start
