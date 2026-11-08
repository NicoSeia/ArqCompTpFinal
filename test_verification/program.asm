# =====================================================================
# programa.asm - programa de validacion del procesador (subset del TP)
# Cubre: R-type, I-type, lui, loads/stores (b/h/w), beq/bne, jal/jalr,
# forwarding, load-use (dist 1/2/3), loops. Termina con halt.
# Solo usa lo soportado por el RTL (sin auipc, sin blt/bge, sin desalineados).
# =====================================================================

# ---- 0. Prologue: dejar x1..x31 en 0 (estado conocido) ----
addi x1,  x0, 0
addi x2,  x0, 0
addi x3,  x0, 0
addi x4,  x0, 0
addi x5,  x0, 0
addi x6,  x0, 0
addi x7,  x0, 0
addi x8,  x0, 0
addi x9,  x0, 0
addi x10, x0, 0
addi x11, x0, 0
addi x12, x0, 0
addi x13, x0, 0
addi x14, x0, 0
addi x15, x0, 0
addi x16, x0, 0
addi x17, x0, 0
addi x18, x0, 0
addi x19, x0, 0
addi x20, x0, 0
addi x21, x0, 0
addi x22, x0, 0
addi x23, x0, 0
addi x24, x0, 0
addi x25, x0, 0
addi x26, x0, 0
addi x27, x0, 0
addi x28, x0, 0
addi x29, x0, 0
addi x30, x0, 0
addi x31, x0, 0

# ---- 1. Limpiar dmem bytes 0..255 con un loop (stores + bne hacia atras) ----
addi x2, x0, 640
clr: sw x0, 0(x1)
addi x1, x1, 4
bne  x1, x2, clr

# ---- 2. R-type con operandos variados (positivos, negativos, shifts >31) ----
addi x1, x0, 5
addi x2, x0, 7
addi x3, x0, -16
addi x4, x0, 33
add  x5, x1, x2         # 12
sub  x6, x2, x1         # 2
sub  x7, x1, x2         # -2
and  x8, x3, x2         # 0xFFFFFFF0 & 7 = 0
or   x9, x3, x2         # 0xFFFFFFF7
xor  x10, x1, x2        # 2
sll  x11, x1, x4        # shift por 33 -> usa [4:0]=1 -> 10
srl  x12, x3, x4        # 0xFFFFFFF0 >> 1 logico
sra  x13, x3, x4        # 0xFFFFFFF0 >>> 1 aritmetico
slt  x14, x3, x1        # -16 < 5 -> 1
slt  x15, x1, x3        # 5 < -16 -> 0
sltu x16, x3, x1        # 0xFFFFFFF0 < 5 -> 0
sltu x17, x1, x3        # 5 < 0xFFFFFFF0 -> 1

# -- guardar resultados (R-type) en dmem[0x100..] --
sw   x5, 256(x0)
sw   x6, 260(x0)
sw   x7, 264(x0)
sw   x8, 268(x0)
sw   x9, 272(x0)
sw   x10, 276(x0)
sw   x11, 280(x0)
sw   x12, 284(x0)
sw   x13, 288(x0)
sw   x14, 292(x0)
sw   x15, 296(x0)
sw   x16, 300(x0)
sw   x17, 304(x0)

# ---- 3. I-type ALU y lui ----
addi  x18, x3, -1       # -17
slti  x19, x3, 0        # 1
slti  x20, x1, -3       # 0
sltiu x21, x1, -1       # 5 < 0xFFFFFFFF -> 1
sltiu x22, x0, 1        # 0 < 1 -> 1
xori  x23, x1, -1       # ~5
ori   x24, x1, 0x70     # 0x75
andi  x25, x3, 0xFF     # 0xF0
slli  x26, x1, 31       # 0x80000000
srli  x27, x26, 31      # 1
srai  x28, x26, 31      # 0xFFFFFFFF
lui   x29, 0x12345
addi  x29, x29, 0x678   # 0x12345678
lui   x30, 0xFFFFF      # 0xFFFFF000
addi  x31, x0, 0

# -- guardar resultados (I-type) en dmem[0x134..] --
sw   x18, 308(x0)
sw   x19, 312(x0)
sw   x20, 316(x0)
sw   x21, 320(x0)
sw   x22, 324(x0)
sw   x23, 328(x0)
sw   x24, 332(x0)
sw   x25, 336(x0)
sw   x26, 340(x0)
sw   x27, 344(x0)
sw   x28, 348(x0)
sw   x29, 352(x0)
sw   x30, 356(x0)
sw   x31, 360(x0)

# ---- 4. Stores y loads de distintos anchos ----
sw   x29, 0(x0)         # mem[0] = 0x12345678
sh   x3,  4(x0)         # half bajo de word 1 = 0xFFF0
sh   x1,  6(x0)         # half alto de word 1 = 5
sb   x1,  8(x0)
sb   x2,  9(x0)
sb   x3,  10(x0)
sb   x4,  11(x0)
lw   x1,  0(x0)         # 0x12345678
lh   x2,  4(x0)         # 0xFFFFFFF0
lhu  x3,  4(x0)         # 0x0000FFF0
lh   x4,  6(x0)         # 5
lb   x5,  10(x0)        # 0xF0 con signo -> 0xFFFFFFF0
lbu  x6,  10(x0)        # 0xF0
lb   x7,  9(x0)         # 7
lbu  x8,  11(x0)        # 33
lw   x9,  8(x0)         # 0x21F00705 (bytes 05 07 F0 21 -> palabra)
lb   x10, 1(x0)         # 0x56
lb   x11, 3(x0)         # 0x12

# -- guardar resultados (loads) en dmem[0x16C..] --
sw   x1, 364(x0)
sw   x2, 368(x0)
sw   x3, 372(x0)
sw   x4, 376(x0)
sw   x5, 380(x0)
sw   x6, 384(x0)
sw   x7, 388(x0)
sw   x8, 392(x0)
sw   x9, 396(x0)
sw   x10, 400(x0)
sw   x11, 404(x0)

# ---- 5. Forwarding encadenado (EX/MEM y MEM/WB) ----
addi x12, x0, 1
add  x13, x12, x12      # 2   (forward EX/MEM)
add  x14, x13, x12      # 3
add  x15, x14, x13      # 5
add  x16, x15, x14      # 8   (mezcla dist 1 y 2)
sub  x17, x16, x12      # 7
sw   x17, 16(x0)
sw   x16, 20(x0)

# -- guardar resultados (forwarding) en dmem[0x198..] --
sw   x12, 408(x0)
sw   x13, 412(x0)
sw   x14, 416(x0)
sw   x15, 420(x0)
sw   x16, 424(x0)
sw   x17, 428(x0)

# ---- 6. Load-use a distancia 1, 2 y 3 ----
lw   x18, 16(x0)        # 7
add  x19, x18, x18      # dist 1 -> 14
lw   x20, 20(x0)        # 8
addi x21, x0, 1
add  x22, x20, x21      # dist 2 -> 9
lw   x23, 16(x0)        # 7
addi x24, x0, 2
addi x25, x0, 3
add  x26, x23, x24      # dist 3 -> 9
# load -> store (dato cargado se guarda)
lw   x27, 20(x0)        # 8
sw   x27, 24(x0)
# load -> direccion de otro load (pointer chasing)
addi x28, x0, 16
sw   x28, 32(x0)        # mem[32] = 16
lw   x29, 32(x0)        # 16
lw   x30, 0(x29)        # mem[16] = 7  (load depende de load)

# -- guardar resultados (load-use) en dmem[0x1B0..] --
sw   x18, 432(x0)
sw   x19, 436(x0)
sw   x20, 440(x0)
sw   x21, 444(x0)
sw   x22, 448(x0)
sw   x23, 452(x0)
sw   x24, 456(x0)
sw   x25, 460(x0)
sw   x26, 464(x0)
sw   x27, 468(x0)
sw   x28, 472(x0)
sw   x29, 476(x0)
sw   x30, 480(x0)

# ---- 7. Branches: tomados/no tomados, adelante y atras ----
addi x1, x0, 3
addi x2, x0, 3
addi x3, x0, 4
addi x4, x0, 0
beq  x1, x2, b1         # tomado
addi x4, x4, 100        # NO debe ejecutarse
b1: bne x1, x3, b2      # tomado
addi x4, x4, 100        # NO
b2: beq x1, x3, b3      # no tomado
addi x4, x4, 1          # SI -> 1
b3: bne x1, x2, b4      # no tomado
addi x4, x4, 2          # SI -> 3
b4: lw  x5, 16(x0)      # 7
addi x6, x0, 7
beq  x5, x6, b5         # load -> branch (dist 1), tomado
addi x4, x4, 100        # NO
b5: addi x7, x0, 0      # contador
addi x8, x0, 5
lp: addi x7, x7, 2      # loop: x7 += 2 cinco veces
addi x8, x8, -1
bne  x8, x0, lp         # x7 = 10, x8 = 0

# -- guardar resultados (branches) en dmem[0x1E4..] --
sw   x4, 484(x0)
sw   x5, 488(x0)
sw   x6, 492(x0)
sw   x7, 496(x0)
sw   x8, 500(x0)

# ---- 8. jal / jalr y link ----
jal  x9, j1             # x9 = pc+4
addi x10, x0, 99        # NO
addi x10, x0, 98        # NO
j1: addi x11, x0, 1
jal  x0, j2             # salto sin link
addi x11, x0, 99        # NO
j2: jal  x12, j3        # salto a la instruccion siguiente: x12 = direccion de j3
j3: jalr x13, 12(x12)   # destino = j3+12; x13 = pc+4
addi x14, x0, 99        # NO
addi x14, x0, 98        # NO
addi x14, x0, 1         # destino del jalr
jalr x15, 25(x12)       # destino impar j3+25 -> bit0 en 0 -> j3+24
addi x16, x0, 97        # NO

# -- guardar resultados (jal/jalr) en dmem[0x1F8..] --
sw   x9, 504(x0)
sw   x10, 508(x0)
sw   x11, 512(x0)
sw   x12, 516(x0)
sw   x13, 520(x0)
sw   x14, 524(x0)
sw   x15, 528(x0)
sw   x16, 532(x0)

# ---- 9. x0 no se escribe ----
addi x0, x0, 55
add  x0, x1, x2
lw   x0, 0(x0)
addi x14, x0, 0
add  x14, x14, x0       # 0

# ---- 10. Fin ----
halt