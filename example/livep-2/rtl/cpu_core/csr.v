module csr(
	input wire clk,    
	input wire rstn,
	input wire [44:0] i_exe_45,		//译码模块数据;44:写使能;43:32:写地址;31:0:写数据;
	output wire [31:0] o_readData_32,	//读数据
	output reg [95:0] o_csrToClint_96,	//CSR给异常处理模块的CSR值
	input wire [128:0] i_clintToCsr_129	//异常处理模块给CSR模块的CSR值和写使能

    );
    
    
	wire w_csrWirte_1;
	wire [11:0] w_addr_12;
	wire [31:0] w_writeData_32;
	assign {w_csrWirte_1,w_addr_12,w_writeData_32}=i_exe_45;  //对45位数据进行划分

	reg  [31:0] csr_mtvec,csr_mcause,csr_mepc,csr_mstatus,csr_mie,csr_mscratch,csr_mtval; //存储CSR的值
	reg  [31:0] r_csrdata_32;

	localparam csr_mtvec_addr    = 12'h305; //CSR地址
	localparam csr_mcause_addr   = 12'h342;
	localparam csr_mepc_addr     = 12'h341;
	localparam csr_mie_addr      = 12'h304;
	localparam csr_mstatus_addr  = 12'h300;
	localparam csr_mscratch_addr = 12'h340;
	localparam csr_mtval_addr    = 12'h343;
   
always@(posedge clk or negedge rstn) 
    begin 
        if (!rstn)begin
        csr_mtvec=0;
        csr_mcause=0;
        csr_mepc=0;
        csr_mstatus=0;
        csr_mie=0;
        csr_mscratch=0;
        csr_mtval=0;
        end              
        else begin
            if(w_csrWirte_1)
	    begin
	    //判断写使能,之后对相应地址进行写数据
            case(w_addr_12)
                csr_mtvec_addr: begin
                    csr_mtvec = w_writeData_32;
                    end
                csr_mcause_addr: begin
                    csr_mcause = w_writeData_32;
                    end
                csr_mepc_addr: begin
                    csr_mepc = w_writeData_32;
                    end
                csr_mie_addr: begin
                    csr_mie = w_writeData_32;
                    end     
                csr_mstatus_addr: begin
                    csr_mstatus = w_writeData_32;
                    end
                csr_mscratch_addr: begin
                    csr_mscratch = w_writeData_32;
                    end
                csr_mtval_addr: begin
                    csr_mtval = w_writeData_32;
                    end
           endcase
           end
	   else if(i_clintToCsr_129[128])
	    //当异常处理给出的使能为1时,改写CSR以保存现场
	    begin
		{csr_mepc,csr_mcause,csr_mtval,csr_mstatus}=i_clintToCsr_129 [127:0]; 
            end
	 end	
  end

always@(*) 
    //对相应地址进行读数据
    begin   
        o_csrToClint_96 = {csr_mtvec,csr_mepc,csr_mstatus};
	case(w_addr_12)
                csr_mtvec_addr: begin
                    r_csrdata_32=csr_mtvec ;
                    end
                csr_mcause_addr: begin
                    r_csrdata_32=csr_mcause ;
                    end
                csr_mepc_addr: begin
                    r_csrdata_32=csr_mepc ;
                    end
                csr_mie_addr: begin
                    r_csrdata_32=csr_mie ;
                    end     
                csr_mstatus_addr: begin
                    r_csrdata_32=csr_mstatus ;
                    end
                csr_mscratch_addr: begin
                   r_csrdata_32= csr_mscratch ;
                    end
                csr_mtval_addr: begin
                   r_csrdata_32= csr_mtval ;
                    end
       endcase
    end

assign o_readData_32=r_csrdata_32;

endmodule
