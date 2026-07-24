; COMMON.INC
; Shared constants and exact MMIO instruction encodings used by T430BLC.
; Compatible with Borland TASM in 16-bit protected-mode code.

SEL_CODE16 equ 08h
SEL_DATA16 equ 10h
SEL_FLAT   equ 18h

PWM_CPU_CTL2_OFFSET equ 048250h
PWM_CPU_CTL_OFFSET  equ 048254h
PWM_PCH_CTL2_OFFSET equ 0C8254h

; TASM's inferred address size is unreliable for these instructions in a
; 16-bit code segment. Keep the verified explicit encodings.
MMIO_READ_EAX_ESI macro
        db      067h,066h,08Bh,006h      ; mov eax,[esi]
endm

MMIO_WRITE_EAX_ESI macro
        db      067h,066h,089h,006h      ; mov [esi],eax
endm
