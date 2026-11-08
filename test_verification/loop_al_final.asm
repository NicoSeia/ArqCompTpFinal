# Directed: el ultimo instruction del programa es un branch tomado hacia atras
# (halt por rango se dispara al pasar del final mientras el branch esta en vuelo).
addi x1, x0, 3
lp: addi x2, x2, 1
addi x1, x1, -1
bne  x1, x0, lp