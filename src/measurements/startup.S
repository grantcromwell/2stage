.syntax unified
.cpu cortex-a9
.arm
.section .vectors,"ax"
.global _start
_start:
    b reset_entry
    b panic_entry
    b panic_entry
    b panic_entry
    b panic_entry
    b panic_entry
    b irq_entry
    b panic_entry
.section .text
reset_entry:
    cpsid if
    mrc p15, 0, r0, c1, c0, 0
    bic r0, r0, #1
    bic r0, r0, #4
    bic r0, r0, #0x1000
    bic r0, r0, #0x2000
    mcr p15, 0, r0, c1, c0, 0
    dsb
    isb
    ldr r0, =_start
    mcr p15, 0, r0, c12, c0, 0
    cps #0x12
    ldr sp, =0x00030000
    cps #0x13
    ldr sp, =0x0002f000
    ldr r0, =__bss_start__
    ldr r1, =__bss_end__
    mov r2, #0
1:  cmp r0, r1
    strlo r2, [r0], #4
    blo 1b
    mov r0, #0
    mcr p15, 0, r0, c7, c5, 0
    mrc p15, 0, r0, c1, c0, 0
    orr r0, r0, #0x1000
    mcr p15, 0, r0, c1, c0, 0
    isb
    bl main
panic_entry:
    ldr r0, =0x0002d000
    ldr r1, =0xdeadc0de
    str r1, [r0]
    str lr, [r0, #4]
2:  b 2b
irq_entry:
    sub lr, lr, #4
    push {r0-r12, lr}
    mrs r0, spsr
    push {r0,r1}
    bl irq_handler
    pop {r0,r1}
    msr spsr_cxsf, r0
    ldmia sp!, {r0-r12, pc}^
