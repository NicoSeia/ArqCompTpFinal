PKG = modules/riscv_pkg.sv
BUILD_DIR = build
DEBUG_DIR = debug_link
MODULES = $(PKG) \
          modules/pc_reg.sv \
          modules/imem.sv \
          modules/control_unit.sv \
          modules/imm_gen.sv \
          modules/regfile.sv \
          modules/alu.sv \
          modules/dmem.sv \
          modules/next_pc_logic.sv
		  
PIPELINE_SRCS = modules/pc_reg.sv modules/imem.sv modules/regfile.sv modules/imm_gen.sv \
                modules/control_unit.sv modules/alu.sv modules/dmem.sv modules/branch_resolve.sv \
                modules/pipe_reg.sv modules/forward_unit.sv modules/hazard_detect.sv modules/pipeline_top.sv

SYSTEM_SRCS = $(PIPELINE_SRCS) $(DEBUG_DIR)/debug_unit.sv \
              $(DEBUG_DIR)/baud_rate_gen.sv $(DEBUG_DIR)/uart_rx.sv \
              $(DEBUG_DIR)/uart_tx.sv $(DEBUG_DIR)/rx_fifo.sv \
              modules/system_top.sv

# Regla por defecto: corre todos los módulos en orden
all: alu regfile regfile_bypass imem dmem imm_gen control_unit next_pc_logic pipe_reg branch_resolve forward_unit hazard_detect datapath_singlecycle pipeline_top debug_unit system_top

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

alu: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/alu.vvp $(PKG) modules/alu.sv tb/tb_alu.sv
	vvp $(BUILD_DIR)/alu.vvp

dmem: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/dmem.vvp $(PKG) modules/dmem.sv tb/tb_dmem.sv
	vvp $(BUILD_DIR)/dmem.vvp

imem: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/imem.vvp $(PKG) modules/imem.sv tb/tb_imem.sv
	vvp $(BUILD_DIR)/imem.vvp

imm_gen: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/imm_gen.vvp $(PKG) modules/imm_gen.sv tb/tb_imm_gen.sv
	vvp $(BUILD_DIR)/imm_gen.vvp

# Viejo, para datapath monociclo
next_pc_logic: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/next_pc_logic.vvp $(PKG) modules/next_pc_logic.sv tb/tb_next_pc_logic.sv
	vvp $(BUILD_DIR)/next_pc_logic.vvp

regfile: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/regfile.vvp $(PKG) modules/regfile.sv tb/tb_regfile.sv
	vvp $(BUILD_DIR)/regfile.vvp

regfile_bypass: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/regfile_bypass.vvp $(PKG) modules/regfile.sv tb/tb_regfile_bypass.sv
	vvp $(BUILD_DIR)/regfile_bypass.vvp

control_unit: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/control_unit.vvp $(PKG) modules/control_unit.sv tb/tb_control_unit.sv
	vvp $(BUILD_DIR)/control_unit.vvp

# Monociclo
datapath_singlecycle: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/datapath_singlecycle.vvp $(MODULES) modules/datapath_singlecycle.sv tb/tb_datapath_singlecycle.sv
	vvp $(BUILD_DIR)/datapath_singlecycle.vvp

# Para el pipeline segmentado
pipe_reg: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/pipe_reg.vvp $(PKG) modules/pipe_reg.sv tb/tb_pipe_reg.sv
	vvp $(BUILD_DIR)/pipe_reg.vvp
 
branch_resolve: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/branch_resolve.vvp $(PKG) modules/branch_resolve.sv tb/tb_branch_resolve.sv
	vvp $(BUILD_DIR)/branch_resolve.vvp

forward_unit: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/forward_unit.vvp $(PKG) modules/forward_unit.sv tb/tb_forward_unit.sv
	vvp $(BUILD_DIR)/forward_unit.vvp

hazard_detect: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/hazard_detect.vvp $(PKG) modules/hazard_detect.sv tb/tb_hazard_detect.sv
	vvp $(BUILD_DIR)/hazard_detect.vvp

# Pipeline segmentado de 5 etapas
pipeline_top: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/pipeline_top.vvp $(PKG) $(PIPELINE_SRCS) tb/tb_pipeline_top.sv
	vvp $(BUILD_DIR)/pipeline_top.vvp

# Debug unit: FSM
debug_unit: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/debug_unit.vvp $(PKG) $(DEBUG_DIR)/debug_unit.sv tb/tb_debug_unit.sv
	vvp $(BUILD_DIR)/debug_unit.vvp

system_top: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/system_top.vvp $(PKG) $(SYSTEM_SRCS) tb/tb_system_top.sv
	vvp $(BUILD_DIR)/system_top.vvp

clean:
	rm -rf $(BUILD_DIR) *.vcd
