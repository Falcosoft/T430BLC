; MMIO.INC
; Exact TASM-safe MMIO DWORD encodings for a 16-bit protected-mode code segment.
;
; DS must select the flat physical-memory segment.
; ESI must contain the physical linear address.

MMIO_READ_EAX_ESI macro
        db 067h,066h,08Bh,006h      ; mov eax,[esi]
endm

MMIO_WRITE_EAX_ESI macro
        db 067h,066h,089h,006h      ; mov [esi],eax
endm
