from __future__ import annotations

from pathlib import Path

from .config import Hardware, ROOT


def _bram(name: str, width: int, depth: int, clock_mhz: int) -> str:
    return f"""
file mkdir "$ip_dir/{name}"
create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 \\
    -module_name {name} -dir "$ip_dir/{name}"
set_property -dict [list \\
    CONFIG.Memory_Type {{True_Dual_Port_RAM}} \\
    CONFIG.Write_Width_A {{{width}}} \\
    CONFIG.Write_Depth_A {{{depth}}} \\
    CONFIG.Read_Width_A {{{width}}} \\
    CONFIG.Write_Width_B {{{width}}} \\
    CONFIG.Read_Width_B {{{width}}} \\
    CONFIG.Enable_B {{Use_ENB_Pin}} \\
    CONFIG.Register_PortA_Output_of_Memory_Primitives {{false}} \\
    CONFIG.Register_PortB_Output_of_Memory_Primitives {{false}} \\
    CONFIG.Operating_Mode_A {{READ_FIRST}} \\
    CONFIG.Operating_Mode_B {{READ_FIRST}} \\
    CONFIG.Interface_Type {{Native}} \\
    CONFIG.PRIM_type_to_Implement {{BRAM}} \\
    CONFIG.Port_A_Clock {{{clock_mhz}}} \\
    CONFIG.Port_B_Clock {{{clock_mhz}}} \\
    CONFIG.Use_Byte_Write_Enable {{true}} \\
    CONFIG.Byte_Size {{8}}] [get_ips {name}]
"""


def _clock(hardware: Hardware) -> str:
    cfg = hardware.clock
    name = cfg.get("name", "clk_wiz_0")
    outputs = list(cfg.get("outputs_mhz", [50.0, 100.0, 200.0]))
    properties = []
    for index, frequency in enumerate(outputs, start=1):
        properties.extend((
            f"CONFIG.CLKOUT{index}_USED {{true}}",
            f"CONFIG.CLKOUT{index}_REQUESTED_OUT_FREQ {{{float(frequency):.3f}}}",
        ))
    property_text = " \\\n    ".join(properties)
    return f"""
file mkdir "$ip_dir/{name}"
create_ip -name clk_wiz -vendor xilinx.com -library ip -version {cfg.get('version', '6.0')} \\
    -module_name {name} -dir "$ip_dir/{name}"
set_property -dict [list \\
    CONFIG.PRIM_IN_FREQ {{{float(cfg.get('input_mhz', 100.0)):.3f}}} \\
    CONFIG.MMCM_CLKIN1_PERIOD {{{1000.0 / float(cfg.get('input_mhz', 100.0)):.3f}}} \\
    CONFIG.MMCM_CLKFBOUT_MULT_F {{{float(cfg.get('feedback_multiplier', 10.0)):.3f}}} \\
    CONFIG.MMCM_DIVCLK_DIVIDE {{{int(cfg.get('input_divider', 1))}}} \\
    {property_text} \\
    CONFIG.RESET_TYPE {{{cfg.get('reset_type', 'ACTIVE_LOW')}}} \\
    CONFIG.USE_LOCKED {{true}} \\
    CONFIG.USE_RESET {{true}}] [get_ips {name}]
"""


def _mig(hardware: Hardware) -> str:
    cfg = hardware.ddr3
    name = cfg.get("name", "mig_axi_32")
    project_file = (ROOT / str(cfg.get("project_file", "docs/Reference/mig/mig_a.prj"))).resolve()
    return f"""
file mkdir "$ip_dir/{name}"
create_ip -name mig_7series -vendor xilinx.com -library ip -version {cfg.get('version', '4.2')} \\
    -module_name {name} -dir "$ip_dir/{name}"
set_property -dict [list \\
    CONFIG.XML_INPUT_FILE {{{project_file.as_posix()}}} \\
    CONFIG.RESET_BOARD_INTERFACE {{Custom}} \\
    CONFIG.MIG_DONT_TOUCH_PARAM {{Custom}}] [get_ips {name}]
"""


def create_ip_tcl(hardware: Hardware, ip_dir: Path) -> str:
    blocks = [
        f"set ip_dir {{{ip_dir.as_posix()}}}\nfile mkdir $ip_dir",
        _bram("ROM", 32, 8192, 100),
        _bram("icached", 256, 16, 50),
        _bram("dcached", 256, 16, 50),
    ]
    names = ["ROM", "icached", "dcached"]
    if hardware.ddr3.get("enabled", True):
        blocks.extend((_clock(hardware), _mig(hardware)))
        names.extend((str(hardware.clock.get("name", "clk_wiz_0")), str(hardware.ddr3.get("name", "mig_axi_32"))))
    blocks.append("set_property -dict [list CONFIG.Load_Init_File {false}] [get_ips ROM]")
    for name in names:
        blocks.append(
            f"generate_target all [get_ips {name}]\n"
            f"export_ip_user_files -of_objects [get_ips {name}] -no_script -sync -force -quiet"
        )
    return "\n".join(blocks)
