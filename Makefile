PKG = modules/riscv_pkg.sv
BUILD_DIR = build
MODULES = $(PKG) \
          modules/pc_reg.sv \
          modules/imem.sv \
          modules/control_unit.sv \
          modules/imm_gen.sv \
          modules/regfile.sv \
          modules/alu.sv \
          modules/dmem.sv \
          modules/next_pc_logic.sv
		  
# Regla por defecto: corre todos los módulos en orden
all: alu dmem imem imm_gen next_pc_logic regfile control_unit datapath_singlecycle

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

next_pc_logic: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/next_pc_logic.vvp $(PKG) modules/next_pc_logic.sv tb/tb_next_pc_logic.sv
	vvp $(BUILD_DIR)/next_pc_logic.vvp

regfile: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/regfile.vvp $(PKG) modules/regfile.sv tb/tb_regfile.sv
	vvp $(BUILD_DIR)/regfile.vvp

control_unit: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/control_unit.vvp $(PKG) modules/control_unit.sv tb/tb_control_unit.sv
	vvp $(BUILD_DIR)/control_unit.vvp

datapath_singlecycle: $(BUILD_DIR)
	iverilog -g2012 -o $(BUILD_DIR)/datapath_singlecycle.vvp $(MODULES) modules/datapath_singlecycle.sv tb/tb_datapath_singlecycle.sv
	vvp $(BUILD_DIR)/datapath_singlecycle.vvp

clean:
	rm -rf $(BUILD_DIR) *.vcd
