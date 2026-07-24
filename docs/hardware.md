# Hardware and register notes

## PCI discovery

The Intel integrated graphics controller is expected at PCI bus 0, device 2, function 0. The utilities read BAR0 dynamically through the PCI BIOS rather than assuming the development machine's physical address.

On the verified T430, BAR0 was:

```text
F0000000h
```

## Active PWM registers

Brightness testing showed that the active Ivy Bridge mobile PWM path is:

```text
BAR0 + 48250h   CPU PWM control/enable
BAR0 + 48254h   CPU PWM duty/control
BAR0 + C8254h   PCH PWM control; maximum in upper word
```

Observed development values:

```text
Minimum:  CPU_CTL = 00000045h
Medium:   CPU_CTL = 000001E7h
Maximum:  CPU_CTL = 00001155h
PCH_CTL2: 11551155h
```

The software reads the maximum from bits 31:16 of `PCH_CTL2`, clamps the requested value, preserves bits 31:16 of `CPU_CTL`, and changes only its low duty word.

## MMIO instruction encoding

The protected-mode code executes in a 16-bit code segment but uses 32-bit registers and addresses. The verified encodings are retained explicitly in `COMMON.INC`:

```text
67 66 8B 06   MOV EAX,[ESI]
67 66 89 06   MOV [ESI],EAX
```

This avoids dependence on TASM's inferred address-size behavior.

## Scope

The project is verified only on the Lenovo ThinkPad T430 configuration listed in the main README. Direct register compatibility with other laptops is not guaranteed.
