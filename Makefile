# Proyecto en Verilog-2001/2005 (migrado desde SystemVerilog).
# -g2005 hace que iverilog rechace cualquier construccion SV (logic,
# always_ff, struct, etc.), asi que si compila aca, es Verilog puro.
# -I modules: para encontrar el header riscv_defs.vh (ex riscv_pkg.sv).
IVFLAGS = -g2005 -I modules
DEFS = modules/riscv_defs.vh
BUILD_DIR = build
DEBUG_DIR = debug_link
MODULES = modules/pc_reg.v \
          modules/imem.v \
          modules/control_unit.v \
          modules/imm_gen.v \
          modules/regfile.v \
          modules/alu.v \
          modules/dmem_comb.v \
          modules/next_pc_logic.v

# Los 4 latches de pipeline: antes era un unico modules/pipe_reg.v generico
# (parametrizado por WIDTH, con offsets de bits armados a mano en cada
# instanciacion). Ahora son 4 modulos con puertos individuales con nombre,
# uno por latch -- eliminan por completo esa cuenta de bits.
PIPE_REGS = modules/if_id_reg.v modules/id_ex_reg.v modules/ex_mem_reg.v modules/mem_wb_reg.v

PIPELINE_SRCS = modules/pc_reg.v modules/imem.v modules/regfile.v modules/imm_gen.v \
                modules/control_unit.v modules/alu.v modules/dmem.v modules/store_align.v modules/load_extract.v \
                modules/branch_resolve.v \
                $(PIPE_REGS) modules/forward_unit.v modules/hazard_detect.v modules/pipeline_top.v

SYSTEM_SRCS = $(PIPELINE_SRCS) $(DEBUG_DIR)/debug_unit.v \
              $(DEBUG_DIR)/baud_rate_gen.v $(DEBUG_DIR)/uart_rx.v \
              $(DEBUG_DIR)/uart_tx.v $(DEBUG_DIR)/rx_fifo.v \
              modules/system_top.v

# Regla por defecto: corre todos los módulos en orden
all: alu regfile regfile_bypass imem dmem dmem_comb store_align load_extract imm_gen control_unit next_pc_logic if_id_reg id_ex_reg ex_mem_reg mem_wb_reg branch_resolve forward_unit hazard_detect datapath_singlecycle pipeline_top pipeline_mem debug_unit system_top

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

alu: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/alu.vvp modules/alu.v tb/tb_alu.v
	vvp $(BUILD_DIR)/alu.vvp

# dmem = BRAM (palabra 32b, byte-enable, lectura sincrona). dmem_comb = la
# vieja combinacional, solo para el monociclo de referencia (no va a la FPGA).
dmem: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/dmem.vvp modules/dmem.v tb/tb_dmem.v
	vvp $(BUILD_DIR)/dmem.vvp

dmem_comb: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/dmem_comb.vvp modules/dmem_comb.v tb/tb_dmem_comb.v
	vvp $(BUILD_DIR)/dmem_comb.vvp

store_align: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/store_align.vvp modules/store_align.v tb/tb_store_align.v
	vvp $(BUILD_DIR)/store_align.vvp

load_extract: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/load_extract.vvp modules/load_extract.v tb/tb_load_extract.v
	vvp $(BUILD_DIR)/load_extract.vvp

imem: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/imem.vvp modules/imem.v tb/tb_imem.v
	vvp $(BUILD_DIR)/imem.vvp

imm_gen: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/imm_gen.vvp modules/imm_gen.v tb/tb_imm_gen.v
	vvp $(BUILD_DIR)/imm_gen.vvp

# Viejo, para datapath monociclo
next_pc_logic: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/next_pc_logic.vvp modules/next_pc_logic.v tb/tb_next_pc_logic.v
	vvp $(BUILD_DIR)/next_pc_logic.vvp

regfile: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/regfile.vvp modules/regfile.v tb/tb_regfile.v
	vvp $(BUILD_DIR)/regfile.vvp

regfile_bypass: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/regfile_bypass.vvp modules/regfile.v tb/tb_regfile_bypass.v
	vvp $(BUILD_DIR)/regfile_bypass.vvp

control_unit: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/control_unit.vvp modules/control_unit.v tb/tb_control_unit.v
	vvp $(BUILD_DIR)/control_unit.vvp

# Monociclo
datapath_singlecycle: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/datapath_singlecycle.vvp $(MODULES) modules/datapath_singlecycle.v tb/tb_datapath_singlecycle.v
	vvp $(BUILD_DIR)/datapath_singlecycle.vvp

# Para el pipeline segmentado: un target por latch (antes uno solo, pipe_reg,
# para el modulo generico parametrizado por WIDTH)
if_id_reg: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/if_id_reg.vvp modules/if_id_reg.v tb/tb_if_id_reg.v
	vvp $(BUILD_DIR)/if_id_reg.vvp

id_ex_reg: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/id_ex_reg.vvp modules/id_ex_reg.v tb/tb_id_ex_reg.v
	vvp $(BUILD_DIR)/id_ex_reg.vvp

ex_mem_reg: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/ex_mem_reg.vvp modules/ex_mem_reg.v tb/tb_ex_mem_reg.v
	vvp $(BUILD_DIR)/ex_mem_reg.vvp

mem_wb_reg: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/mem_wb_reg.vvp modules/mem_wb_reg.v tb/tb_mem_wb_reg.v
	vvp $(BUILD_DIR)/mem_wb_reg.vvp

branch_resolve: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/branch_resolve.vvp modules/branch_resolve.v tb/tb_branch_resolve.v
	vvp $(BUILD_DIR)/branch_resolve.vvp

forward_unit: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/forward_unit.vvp modules/forward_unit.v tb/tb_forward_unit.v
	vvp $(BUILD_DIR)/forward_unit.vvp

hazard_detect: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/hazard_detect.vvp modules/hazard_detect.v tb/tb_hazard_detect.v
	vvp $(BUILD_DIR)/hazard_detect.vvp

# Pipeline segmentado de 5 etapas
pipeline_top: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/pipeline_top.vvp $(PIPELINE_SRCS) tb/tb_pipeline_top.v
	vvp $(BUILD_DIR)/pipeline_top.vvp

# Camino de memoria completo (sb/sh/sw, lb/lbu/lh/lhu/lw, load-use, enable aleatorio + debug aleatorio)
pipeline_mem: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/pipeline_mem.vvp $(PIPELINE_SRCS) tb/tb_pipeline_mem.v
	vvp $(BUILD_DIR)/pipeline_mem.vvp

# Debug unit: FSM
debug_unit: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/debug_unit.vvp $(DEBUG_DIR)/debug_unit.v tb/tb_debug_unit.v
	vvp $(BUILD_DIR)/debug_unit.vvp

system_top: $(BUILD_DIR)
	iverilog $(IVFLAGS) -o $(BUILD_DIR)/system_top.vvp $(SYSTEM_SRCS) tb/tb_system_top.v
	vvp $(BUILD_DIR)/system_top.vvp

clean:
	rm -rf $(BUILD_DIR) *.vcd

.PHONY: all clean alu dmem dmem_comb store_align load_extract imem imm_gen next_pc_logic regfile regfile_bypass control_unit datapath_singlecycle if_id_reg id_ex_reg ex_mem_reg mem_wb_reg branch_resolve forward_unit hazard_detect pipeline_top pipeline_mem debug_unit system_top