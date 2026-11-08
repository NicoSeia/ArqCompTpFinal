# algoritmos.asm -- programa de verificacion #2
# Fibonacci, bubble sort, MCD, popcount, multiplicacion por subrutina,
# copia de bytes y accesos byte/halfword con signo.
# Solo usa el subset soportado: beq/bne, sin mul ni blt/bge.
# Resultados en dmem 0x000..0x1BF (dentro de los 640 bytes que se vuelcan).

# ---------- 0) limpia dmem 0..639 (la dmem de la placa puede tener datos viejos) ----------
addi x5, x0, 0
addi x6, x0, 160
clr: sw x0, 0(x5)
addi x5, x5, 4
addi x6, x6, -1
bne  x6, x0, clr

# ---------- 1) Fibonacci: 16 numeros en dmem[0x000..0x03C] ----------
addi x5, x0, 0
addi x6, x0, 1
addi x7, x0, 0
addi x8, x0, 16
fib: sw x5, 0(x7)
add  x9, x5, x6
addi x5, x6, 0
addi x6, x9, 0
addi x7, x7, 4
addi x8, x8, -1
bne  x8, x0, fib

# ---------- 2) Bubble sort de 8 enteros con signo en dmem[0x100..0x11C] ----------
addi x5, x0, 9
sw   x5, 0x100(x0)
addi x5, x0, 3
sw   x5, 0x104(x0)
addi x5, x0, -5
sw   x5, 0x108(x0)
addi x5, x0, 1
sw   x5, 0x10C(x0)
addi x5, x0, 8
sw   x5, 0x110(x0)
addi x5, x0, 2
sw   x5, 0x114(x0)
addi x5, x0, -6
sw   x5, 0x118(x0)
addi x5, x0, 4
sw   x5, 0x11C(x0)
addi x10, x0, 7
outer: addi x11, x0, 0x100
addi x13, x0, 7
inner: lw  x14, 0(x11)
lw   x15, 4(x11)
slt  x16, x15, x14
beq  x16, x0, noswap
sw   x15, 0(x11)
sw   x14, 4(x11)
noswap: addi x11, x11, 4
addi x13, x13, -1
bne  x13, x0, inner
addi x10, x10, -1
bne  x10, x0, outer

# ---------- 3) MCD(84, 36) por restas -> dmem[0x40] ----------
addi x17, x0, 84
addi x18, x0, 36
gcd: beq x17, x18, gdone
slt  x19, x17, x18
bne  x19, x0, bmayor
sub  x17, x17, x18
jal  x0, gcd
bmayor: sub x18, x18, x17
jal  x0, gcd
gdone: sw x17, 0x40(x0)

# ---------- 4) popcount(0xF0F0A5A5) = 16 -> dmem[0x44] ----------
lui  x20, 0xF0F0A
addi x20, x20, 0x5A5
addi x21, x0, 0
addi x22, x0, 32
pc: andi x23, x20, 1
add  x21, x21, x23
srli x20, x20, 1
addi x22, x22, -1
bne  x22, x0, pc
sw   x21, 0x44(x0)

# ---------- 5) subrutina mul (suma y desplazamiento) con jal/jalr ----------
addi x10, x0, 13
addi x11, x0, 11
jal  x1, mul
sw   x12, 0x48(x0)
addi x10, x0, 1000
addi x11, x0, 25
jal  x1, mul
sw   x12, 0x4C(x0)

# ---------- 6) copia de 32 bytes: 0x100 -> 0x180 (lbu/sb) ----------
addi x5, x0, 0x100
addi x6, x0, 0x180
addi x7, x0, 32
cp: lbu x8, 0(x5)
sb   x8, 0(x6)
addi x5, x5, 1
addi x6, x6, 1
addi x7, x7, -1
bne  x7, x0, cp

# ---------- 7) byte/halfword con signo ----------
lui  x9, 0x80008
addi x9, x9, 1
sw   x9, 0x1A0(x0)
lh   x10, 0x1A0(x0)
sw   x10, 0x1A4(x0)
lhu  x11, 0x1A0(x0)
sw   x11, 0x1A8(x0)
lb   x12, 0x1A3(x0)
sw   x12, 0x1AC(x0)
lbu  x13, 0x1A3(x0)
sw   x13, 0x1B0(x0)
sh   x9, 0x1B4(x0)
sb   x9, 0x1B8(x0)
addi x0, x0, 5
add  x14, x0, x0
sw   x14, 0x1BC(x0)
halt

# ---------- subrutina mul(x10, x11) -> x12, retorno por x1 ----------
mul: addi x12, x0, 0
mloop: beq x11, x0, mdone
andi x28, x11, 1
beq  x28, x0, mskip
add  x12, x12, x10
mskip: slli x10, x10, 1
srli x11, x11, 1
jal  x0, mloop
mdone: jalr x0, 0(x1)