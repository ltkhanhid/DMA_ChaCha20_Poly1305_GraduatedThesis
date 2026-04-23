# Test CSR instructions with GNU assembler
.section .text
.globl _start

_start:
    # Setup trap handler
    la   t0, trap_handler
    csrw mtvec, t0
    
    # Enable timer interrupt
    li   t0, 0x80
    csrs mie, t0
    
    # Enable global interrupt
    li   t0, 0x8
    csrs mstatus, t0
    
    # Main loop
main_loop:
    nop
    j    main_loop

.align 4
trap_handler:
    # Simple handler
    csrr t0, mcause
    mret
