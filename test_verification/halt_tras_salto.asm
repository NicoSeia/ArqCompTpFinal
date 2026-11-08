# Directed: salto tomado seguido inmediatamente de una instruccion ilegal/halt
# (la instruccion de la sombra del salto NO debe provocar un halt).
addi x1, x0, 1
jal  x0, fin
halt                    # camino equivocado: no debe ejecutarse ni disparar halt
halt
fin: addi x2, x0, 2
addi x3, x0, 3
halt