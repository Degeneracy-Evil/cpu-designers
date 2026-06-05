# =============================================================================
# gen_ddr_controller.tcl — 通过 TCL 命令复现生成 bd_soc_ddr_controller_0 IP
#
# 用法:
#   vivado -mode tcl
#   source gen_ddr_controller.tcl -notrace
#
# 说明:
#   本脚本在 test 项目中创建 mig_7series IP (DDR3 控制器),
#   配置参数来源于 bd_soc_ddr_controller_0.xci 的解析结果。
#
#   MIG 7 Series IP 的核心配置由 XML_INPUT_FILE (mig_a.prj) 决定,
#   该文件包含 DDR3 引脚分配、时序参数、FPGA bank 选择等。
#   如果 mig_a.prj 不存在, 脚本将先生成一个默认模板供用户修改。
#
# IP 配置摘要:
#   - IP 类型:     mig_7series v4.2
#   - 实例名:      bd_soc_ddr_controller_0
#   - 内存类型:    DDR3
#   - 数据速率:    800 MHz (1250 ps 周期)
#   - 参考时钟:    100 MHz 差分 (DIFF)
#   - CAS 延迟:    11
#   - 数据宽度:    8 bit (component)
#   - 地址宽度:    8 bit
#   - Bank 宽度:   3 bit
#   - 行宽:        14 bit
#   - ECC:         OFF
#   - Debug Port:  OFF
#   - AXI:         未启用
#   - MMCM VCO:    1200.0 MHz
# =============================================================================

# ---------------------------------------------------------------------------
# 路径与配置
# ---------------------------------------------------------------------------
set base_dir        [file dirname [file normalize [info script]]]
set proj_name       "test"
set device_part     "xc7a200tfbg676-2"
set proj_dir        "${base_dir}/${proj_name}"

set ip_name         "bd_soc_ddr_controller_0"
set ip_vendor       "xilinx.com"
set ip_library      "ip"
set ip_module       "mig_7series"
set ip_version      "4.2"

# MIG 项目文件 (包含引脚分配和详细时序参数)
set mig_prj_file    "${base_dir}/${ip_name}/mig_a.prj"

puts "========================================"
puts "生成 DDR3 控制器 IP: ${ip_name}"
puts "目标工程: ${proj_dir}/${proj_name}.xpr"
puts "器件: ${device_part}"
puts "========================================"

# ---------------------------------------------------------------------------
# Step 1: 创建或打开工程
# ---------------------------------------------------------------------------
puts "========== Step 1: 创建/打开工程 =========="

set cur_proj [current_project -quiet]
if { $cur_proj ne "" } {
    if { $cur_proj eq $proj_name } {
        puts "工程已打开: $cur_proj"
    } else {
        puts "关闭当前工程: $cur_proj"
        catch { close_project }
        set cur_proj ""
    }
}

if { $cur_proj eq "" } {
    set xpr_path "${proj_dir}/${proj_name}.xpr"
    if { [file exists $xpr_path] } {
        puts "打开已有工程: $xpr_path"
        open_project $xpr_path
    } else {
        puts "创建新工程: ${proj_dir}"
        create_project $proj_name $proj_dir -part $device_part -force
        set_property target_language Verilog [current_project]
        set_property simulator_language Mixed [current_project]
    }
}

# ---------------------------------------------------------------------------
# Step 2: 检查 MIG 项目文件 (mig_a.prj)
# ---------------------------------------------------------------------------
puts "========== Step 2: 检查 MIG 项目文件 =========="

if { ![file exists $mig_prj_file] } {
    puts "WARNING: MIG 项目文件不存在: $mig_prj_file"
    puts "  MIG 7 Series IP 需要 mig_a.prj 文件来定义引脚分配和时序参数。"
    puts "  正在生成默认模板..."

    # 生成默认的 mig_a.prj 模板
    # 注意: 用户必须根据实际 PCB 引脚分配修改此文件!
    set mig_prj_content {<?xml version='1.0' encoding='UTF-8'?>
<Project NoOfControllers="1">
  <ModuleName>bd_soc_ddr_controller_0</ModuleName>
  <dci_inouts_inputs>1</dci_inouts_inputs>
  <dci_outputs>1</dci_outputs>
  <Debug_En>0</Debug_En>
  <DataDepth_En>0</DataDepth_En>
  <Desc_En>0</Desc_En>
  <BoundaryDesc>0</BoundaryDesc>
  <Disp_En>0</Disp_En>
  <PeriphType>UART</PeriphType>
  <MCType>1</MCType>
  <HCType>0</HCType>
  <FPGADevice>xc7a200tfbg676-2</FPGADevice>
  <HardMacroFile></HardMacroFile>
  <Controller number="0">
    <MemoryType>DDR3</MemoryType>
    <TimePeriod>1250</TimePeriod>
    <VccAuxIO>1.8V</VccAuxIO>
    <TopRouting>0</TopRouting>
    <ByteMap>R0C0</ByteMap>
    <InternalVref>0</InternalVref>
    <MemoryDataWidth>8</MemoryDataWidth>
    <BankSelectionFlag>0</BankSelectionFlag>
    <ControllerBanks>
      <!-- 用户需根据实际 PCB 修改 Bank 分配 -->
      <Bank>15</Bank>
      <Bank>14</Bank>
    </ControllerBanks>
    <DataPinBank>15</DataPinBank>
    <DQSPinBank>15</DQSPinBank>
    <AddressPinBank>14</AddressPinBank>
    <ClockPinBank>14</ClockPinBank>
    <PinSelection>
      <Pin VCCAUX_IO="" IOSTANDARD="SSTL15" PADNAME="A2" name="ddr3_dq[0]" />
      <Pin VCCAUX_IO="" IOSTANDARD="SSTL15" PADNAME="B2" name="ddr3_dq[1]" />
      <Pin VCCAUX_IO="" IOSTANDARD="SSTL15" PADNAME="C2" name="ddr3_dq[2]" />
      <Pin VCCAUX_IO="" IOSTANDARD="SSTL15" PADNAME="D2" name="ddr3_dq[3]" />
      <Pin VCCAUX_IO="" IOSTANDARD="SSTL15" PADNAME="E2" name="ddr3_dq[4]" />
      <Pin VCCAUX_IO="" IOSTANDARD="SSTL15" PADNAME="F2" name="ddr3_dq[5]" />
      <Pin VCCAUX_IO="" IOSTANDARD="SSTL15" PADNAME="G2" name="ddr3_dq[6]" />
      <Pin VCCAUX_IO="" IOSTANDARD="SSTL15" PADNAME="H2" name="ddr3_dq[7]" />
      <Pin VCCAUX_IO="" IOSTANDARD="SSTL15" PADNAME="A3" name="ddr3_dqs_p" />
      <Pin VCCAUX_IO="" IOSTANDARD="SSTL15" PADNAME="B3" name="ddr3_dqs_n" />
      <Pin VCCAUX_IO="" IOSTANDARD="SSTL15" PADNAME="C3" name="ddr3_dm" />
      <!-- 用户需补充: ddr3_addr, ddr3_ba, ddr3_ras_n, ddr3_cas_n, ddr3_we_n, -->
      <!-- ddr3_reset_n, ddr3_ck_p, ddr3_ck_n, ddr3_cke, ddr3_cs_n, ddr3_odt -->
      <!-- 以及 clk_ref_p, clk_ref_n, sys_rst 引脚 -->
    </PinSelection>
    <SystemClock>
      <Pin PADNAME="R3" name="clk_ref_p" />
      <Pin PADNAME="T3" name="clk_ref_n" />
    </SystemClock>
    <SystemReset>
      <Pin PADNAME="U4" name="sys_rst" />
    </SystemReset>
    <TimingParameters>
      <Parameters twr="15" trrd="6" trcd="11" tras="35" trp="11" trfc="260" tfaw="30" trtp="11" />
    </TimingParameters>
    <MemoryParameters>
      <Parameters trefi="7800" />
    </MemoryParameters>
    <CustomPart>FALSE</CustomPart>
    <NewPartName></NewPartName>
    <RowAddress>14</RowAddress>
    <ColAddress>10</ColAddress>
    <BankAddress>3</BankAddress>
    <MemoryPart>MT41K128M16XX-15E</MemoryPart>
    <NoOfBuffers>4</NoOfBuffers>
    <RSTPolariy>ACTIVE_LOW</RSTPolariy>
    <InputClk>DIFF</InputClk>
    <OutputClk>0</OutputClk>
    <ClkGenEn>0</ClkGenEn>
    <ClkGen1En>0</ClkGen1En>
    <ClkGen2En>0</ClkGen2En>
    <ClkGen3En>0</ClkGen3En>
    <ClkGen4En>0</ClkGen4En>
    <DataMask>1</DataMask>
    <ECC>0</ECC>
    <Ordering>Normal</Ordering>
    <BankMapNum>0</BankMapNum>
    <BankMapSwap>00</BankMapSwap>
    <CSOveride>0</CSOveride>
    <ODTAssertion>2</ODTAssertion>
    <Parity>0</Parity>
    <ParityErrorLogEn>0</ParityErrorLogEn>
    <ParityEndLatency>3</ParityEndLatency>
    <CRC>0</CRC>
    <CRCLatency>3</CRCLatency>
    <IdleCtrl>0</IdleCtrl>
    <BurstMode>OTF</BurstMode>
    <BurstLength>8</BurstLength>
    <ReadDBI>0</ReadDBI>
    <WriteDBI>0</WriteDBI>
    <OutputEn>0</OutputEn>
    <PipeLatency>0</PipeLatency>
    <SimMode>0</SimMode>
    <RegMode>0</RegMode>
    <DqRxTaps>0</DqRxTaps>
    <DqRxEnTap>0</DqRxEnTap>
    <DqRxDlyTap>0</DqRxDlyTap>
    <DqTxTaps>0</DqTxTaps>
    <DqsRxTaps>0</DqsRxTaps>
    <DqsRxEnTap>0</DqsRxEnTap>
    <DqsRxDlyTap>0</DqsRxDlyTap>
    <DqsTxTaps>0</DqsTxTaps>
    <DqsTxEnTap>0</DqsTxEnTap>
    <DqsTxDlyTap>0</DqsTxDlyTap>
    <PhaserRefClkSel>0</PhaserRefClkSel>
    <RstLow>1</RstLow>
    <DqsSwap>0</DqsSwap>
    <DqSwap>0</DqSwap>
    <DqsMap>0</DqsMap>
    <DqMap>0</DqMap>
    <BankGroupSwap>0</BankGroupSwap>
    <DqsByteMapSwap>0</DqsByteMapSwap>
    <DqsByteMap>0</DqsByteMap>
    <DqBitMap>0</DqBitMap>
    <ClkSel>0</ClkSel>
    <ClkDis>1</ClkDis>
    <CkeDis>0</CkeDis>
    <OdtDis>0</OdtDis>
    <CsDis>0</CsDis>
    <AddCmdLatency>0</AddCmdLatency>
    <MemInitEn>0</MemInitEn>
    <MemInitFile></MemInitFile>
    <MemInitPat>0</MemInitPat>
    <AppEn>0</AppEn>
    <AppWdtEn>0</AppWdtEn>
    <AppWdtTime>0</AppWdtTime>
    <TwoTEn>0</TwoTEn>
    <TwoTCmd>0</TwoTCmd>
    <TwoTAddr>0</TwoTAddr>
    <TwoTClk>0</TwoTClk>
    <TwoTBank>0</TwoTBank>
    <TwoTCke>0</TwoTCke>
    <TwoTOdt>0</TwoTOdt>
    <TwoTCs>0</TwoTCs>
    <PIEn>0</PIEn>
    <DCIEn>0</DCIEn>
    <DCIVal>0</DCIVal>
    <DCIEnVal>0</DCIEnVal>
    <DCIUpdEn>0</DCIUpdEn>
    <DCIUpdVal>0</DCIUpdVal>
  </Controller>
</Project>}

    # 确保目录存在
    set mig_prj_dir [file dirname $mig_prj_file]
    if { ![file exists $mig_prj_dir] } {
        file mkdir $mig_prj_dir
    }

    set fp [open $mig_prj_file w]
    puts -nonewline $fp $mig_prj_content
    close $fp

    puts "  已生成默认模板: $mig_prj_file"
    puts "  *** 请根据实际 PCB 引脚分配修改此文件后重新运行脚本! ***"
}

# ---------------------------------------------------------------------------
# Step 3: 创建 MIG 7 Series IP
# ---------------------------------------------------------------------------
puts "========== Step 3: 创建 MIG 7 Series IP =========="

# 检查 IP 是否已存在
set existing_ip [get_ips -quiet $ip_name]
if { $existing_ip ne "" } {
    puts "IP 已存在: $ip_name, 删除后重新创建..."
    catch { remove_ip $existing_ip }
}

# 创建 IP 核
puts "创建 IP: ${ip_module} v${ip_version} (实例名: ${ip_name})"
create_ip -name $ip_module -vendor $ip_vendor -library $ip_library -version $ip_version -module_name $ip_name

# ---------------------------------------------------------------------------
# Step 4: 配置 IP 参数
# ---------------------------------------------------------------------------
puts "========== Step 4: 配置 IP 参数 =========="

# MIG 7 Series 的核心配置通过 XML_INPUT_FILE 指定
# 该 .prj 文件包含: 引脚分配、Bank 选择、时序参数、内存型号等
set_property -dict [list \
    CONFIG.XML_INPUT_FILE    $mig_prj_file \
    CONFIG.RESET_BOARD_INTERFACE {Custom} \
] [get_ips $ip_name]

puts "IP 参数已配置:"
puts "  XML_INPUT_FILE       = $mig_prj_file"
puts "  RESET_BOARD_INTERFACE = Custom"

# ---------------------------------------------------------------------------
# Step 5: 生成 IP 目标
# ---------------------------------------------------------------------------
puts "========== Step 5: 生成 IP 目标 =========="

set ip_obj [get_ips $ip_name]

if { $ip_obj eq "" } {
    puts "ERROR: 无法获取 IP 对象: $ip_name"
    return
}

# 生成 IP 输出产品
if { [catch {generate_target all $ip_obj} err] } {
    puts "ERROR: generate_target 失败: $err"
    puts "  可能原因: mig_a.prj 文件中的引脚分配与目标器件不匹配"
    puts "  请修改 $mig_prj_file 后重新运行"
    return
}

# 导出 IP 缓存
catch { config_ip_cache -export $ip_obj }

# 导出 IP 用户文件
export_ip_user_files -of_objects $ip_obj -no_script -sync -force -quiet

# 更新编译顺序
update_compile_order -fileset sources_1

puts "========================================"
puts "DDR3 控制器 IP 生成完成!"
puts "  IP 名称:   $ip_name"
puts "  IP 类型:   $ip_module v$ip_version"
puts "  内存类型:  DDR3"
puts "  数据速率:  800 MHz"
puts "  参考时钟:  100 MHz 差分"
puts "  工程:      ${proj_dir}/${proj_name}.xpr"
puts "========================================"

# ---------------------------------------------------------------------------
# 可选: 生成 IP 的仿真模型和综合后检查点
# ---------------------------------------------------------------------------
puts "========== 可选: 导出仿真模型 =========="

catch {
    set ip_src_dir "${proj_dir}/${proj_name}.srcs/sources_1/ip/${ip_name}"
    if { [file exists $ip_src_dir] } {
        puts "IP 源文件目录: $ip_src_dir"
        # 列出生成的文件
        foreach f [glob -directory $ip_src_dir *] {
            puts "  [file tail $f]"
        }
    }
}

puts "脚本执行完成。"
