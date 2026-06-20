// NS16550A UART Register Module
// Adapted from chiplab IP/APB_DEV/URT/uart_regs.v
//
// NS16550A compliance fixes vs chiplab original:
// 1. Removed 3rd divisor byte (DL3) — 16-bit divisor only (DLL/DLM)
// 2. Restored SCR (Scratch Register) at offset 7 (was USART mode_reg/fi_di_reg)
// 3. Fixed MCR read — added to read mux at offset 4
// 4. Removed USART extensions (mode_reg, fi_di_reg, repeat_reg, sclk, IrDA, rx_pol)
// 5. Removed M_cnt/M_toggle (DL3-based clock modulation)
// 6. Simplified transmitter connection (no USART T0/T1 repeat logic)

`include "uart_defines.svh"

`define UART_DL1 7:0
`define UART_DL2 15:8

module uart_regs_16550a (
    input  wire        clk,
    input  wire        rst,
    input  wire [2:0]  addr,       // Register select (byte offset 0-7)
    input  wire [7:0]  dat_i,      // Write data (8-bit)
    output reg  [7:0]  dat_o,      // Read data (8-bit)
    input  wire        we,         // Write enable
    input  wire        re,         // Read enable

    // Modem
    input  wire [3:0]  modem_inputs,  // {CTS, DSR, RI, DCD}
    output wire        rts_pad_o,
    output wire        dtr_pad_o,

    // Serial
    output wire        stx_pad_o,
    input  wire        srx_pad_i,

    // Interrupt
    output reg         int_o
);

    // ----------------------------------------------------------------
    // Internal signals
    // ----------------------------------------------------------------
    reg        enable;         // Baud rate clock enable (1 pulse per divisor period)

    // Registers
    reg  [3:0] ier;            // Interrupt Enable Register
    reg  [3:0] iir;            // Interrupt Identification Register
    reg  [1:0] fcr;            // FIFO Control Register (only trigger level bits [7:6])
    reg  [4:0] mcr;            // Modem Control Register
    reg  [7:0] lcr;            // Line Control Register
    reg  [7:0] msr;            // Modem Status Register
    reg  [7:0] scr;            // Scratch Register (NS16550A standard)
    reg  [15:0] dl;            // Divisor Latch (DLL=dl[7:0], DLM=dl[15:8])
    reg        start_dlc;
    reg        msi_reset;

    reg  [15:0] dlc;           // Divisor latch down-counter
    reg  [3:0]  trigger_level;
    reg        rx_reset;
    reg        tx_reset;

    wire dlab = lcr[`UART_LC_DL];   // Divisor Latch Access Bit

    // ----------------------------------------------------------------
    // Modem signals
    // ----------------------------------------------------------------
    wire cts_pad_i, dsr_pad_i, ri_pad_i, dcd_pad_i;
    wire loopback;
    wire cts, dsr, ri, dcd;
    wire cts_c, dsr_c, ri_c, dcd_c;

    assign {cts_pad_i, dsr_pad_i, ri_pad_i, dcd_pad_i} = modem_inputs;
    assign {cts, dsr, ri, dcd} = ~{cts_pad_i, dsr_pad_i, ri_pad_i, dcd_pad_i};  // Inverted inputs

    assign loopback = mcr[4];  // MCR bit 4 = loopback

    assign {cts_c, dsr_c, ri_c, dcd_c} = loopback ?
        {mcr[`UART_MC_RTS], mcr[`UART_MC_DTR], mcr[`UART_MC_OUT1], mcr[`UART_MC_OUT2]} :
        {cts_pad_i, dsr_pad_i, ri_pad_i, dcd_pad_i};

    assign rts_pad_o = mcr[`UART_MC_RTS];
    assign dtr_pad_o = mcr[`UART_MC_DTR];

    // ----------------------------------------------------------------
    // Transmitter & Receiver
    // ----------------------------------------------------------------
    wire rls_int, rda_int, ti_int, thre_int, ms_int;

    wire tf_push;
    reg  rf_pop;
    wire [`UART_FIFO_REC_WIDTH-1:0]  rf_data_out;
    wire rf_error_bit;
    wire [`UART_FIFO_COUNTER_W-1:0]  rf_count;
    wire [`UART_FIFO_COUNTER_W-1:0]  tf_count;
    wire [2:0]  tstate;
    wire [9:0]  counter_t;

    wire thre_set_en;

    wire serial_out;

    // Forward-declare lsr_mask (needed by transmitter before full LSR logic)
    wire lsr_mask_condition = (re && addr == `UART_REG_LS && !dlab);
    wire iir_read           = (re && addr == `UART_REG_II && !dlab);
    wire msr_read           = (re && addr == `UART_REG_MS && !dlab);
    wire fifo_read          = (re && addr == `UART_REG_RB && !dlab);
    wire fifo_write         = (we && addr == `UART_REG_TR && !dlab);

    reg lsr_mask_d;
    always @(posedge clk) begin
        if (rst)
            lsr_mask_d <= 1'b0;
        else
            lsr_mask_d <= lsr_mask_condition;
    end

    wire lsr_mask = lsr_mask_condition && ~lsr_mask_d;

    uart_transmitter transmitter (
        .clk      (clk),
        .wb_rst_i (rst),
        .lcr      (lcr),
        .tf_push  (tf_push),
        .wb_dat_i (dat_i),
        .enable   (enable),
        .stx_pad_o(serial_out),
        .tstate   (tstate),
        .tf_count (tf_count),
        .tx_reset (tx_reset),
        .lsr_mask (lsr_mask)
    );

    // RX synchronizer (2-stage)
    wire srx_pad;
    uart_sync_flops #(
        .WIDTH      (1),
        .INIT_VALUE (1'b1)
    ) i_uart_sync_flops (
        .rst_i           (rst),
        .clk_i           (clk),
        .stage1_rst_i    (1'b0),
        .stage1_clk_en_i (1'b1),
        .async_dat_i     (loopback ? serial_out : srx_pad_i),
        .sync_dat_o      (srx_pad)
    );

    wire rf_overrun;
    wire rf_push_pulse;

    uart_receiver receiver (
        .clk          (clk),
        .wb_rst_i     (rst),
        .lcr          (lcr),
        .rf_pop       (rf_pop),
        .srx_pad_i    (srx_pad),
        .enable       (enable),
        .counter_t    (counter_t),
        .rf_count     (rf_count),
        .rf_data_out  (rf_data_out),
        .rf_error_bit (rf_error_bit),
        .rf_overrun   (rf_overrun),
        .rx_reset     (rx_reset),
        .lsr_mask     (lsr_mask),
        .rstate       (),
        .rf_push_pulse(rf_push_pulse)
    );

    // TX output: loopback → idle (1), break → 0, normal → serial_out
    assign stx_pad_o = lcr[`UART_LC_BC] ? 1'b0 : serial_out;

    // ----------------------------------------------------------------
    // Register Read Mux
    // ----------------------------------------------------------------
    always @(*) begin
        case (addr)
        `UART_REG_RB: dat_o = dlab ? dl[`UART_DL1] : rf_data_out[10:3];  // RBR or DLL
        `UART_REG_IE: dat_o = dlab ? dl[`UART_DL2] : {4'b0, ier};        // IER or DLM
        `UART_REG_II: dat_o = dlab ? 8'b0 : {4'b1100, iir};              // IIR (DLAB=1: 0, no DL3)
        `UART_REG_LC: dat_o = lcr;                                         // LCR
        `UART_REG_MC: dat_o = {3'b0, mcr};                                 // MCR (FIXED: now readable)
        `UART_REG_LS: dat_o = lsr;                                         // LSR
        `UART_REG_MS: dat_o = msr;                                         // MSR
        `UART_REG_SR: dat_o = scr;                                         // SCR (FIXED: standard scratch)
        default:     dat_o = 8'b0;
        endcase
    end

    // ----------------------------------------------------------------
    // RF pop control
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            rf_pop <= 1'b0;
        else if (rf_pop)
            rf_pop <= 1'b0;
        else if (re && addr == `UART_REG_RB && !dlab)
            rf_pop <= 1'b1;
    end

    // ----------------------------------------------------------------
    // Pulse generators for interrupt clearing (lsr_mask, iir_read, etc.
    // already declared above before transmitter instantiation)
    // ----------------------------------------------------------------

    always @(posedge clk) begin
        if (rst)
            msi_reset <= 1'b1;
        else if (msi_reset)
            msi_reset <= 1'b0;
        else if (msr_read)
            msi_reset <= 1'b1;
    end

    // ----------------------------------------------------------------
    // Register Write: LCR
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            lcr <= 8'b00000011;   // 8N1, DLAB=0
        else if (we && addr == `UART_REG_LC)
            lcr <= dat_i;
    end

    // ----------------------------------------------------------------
    // Register Write: IER / DLM
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            ier <= 4'b0000;
            dl[`UART_DL2] <= 8'b0;
        end else if (we && addr == `UART_REG_IE) begin
            if (dlab)
                dl[`UART_DL2] <= dat_i;
            else
                ier <= dat_i[3:0];
        end
    end

    // ----------------------------------------------------------------
    // Register Write: FCR / (DL3 removed — no-op when DLAB=1)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            fcr      <= 2'b11;    // Trigger level = 14
            rx_reset <= 1'b0;
            tx_reset <= 1'b0;
        end else if (we && addr == `UART_REG_FC) begin
            if (!dlab) begin       // DLAB=1: no-op (DL3 removed)
                fcr      <= dat_i[7:6];
                rx_reset <= dat_i[1];
                tx_reset <= dat_i[2];
            end
        end else begin
            rx_reset <= 1'b0;
            tx_reset <= 1'b0;
        end
    end

    // ----------------------------------------------------------------
    // Register Write: MCR
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            mcr <= 5'b0;
        else if (we && addr == `UART_REG_MC)
            mcr <= dat_i[4:0];
    end

    // ----------------------------------------------------------------
    // Register Write: SCR (Scratch Register)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            scr <= 8'b0;
        else if (we && addr == `UART_REG_SR)
            scr <= dat_i;
    end

    // ----------------------------------------------------------------
    // THR push / DLL write
    // ----------------------------------------------------------------
    assign tf_push = we & (addr == `UART_REG_TR) & !dlab;

    always @(posedge clk) begin
        if (rst) begin
            dl[`UART_DL1] <= 8'b0;
            start_dlc     <= 1'b0;
        end else if (we && addr == `UART_REG_TR) begin
            if (dlab) begin
                dl[`UART_DL1] <= dat_i;
                start_dlc     <= 1'b1;
            end else begin
                start_dlc <= 1'b0;
            end
        end else begin
            start_dlc <= 1'b0;
        end
    end

    // ----------------------------------------------------------------
    // FIFO trigger level
    // ----------------------------------------------------------------
    always @(*) begin
        case (fcr[`UART_FC_TL])
        2'b00: trigger_level = 4'd1;
        2'b01: trigger_level = 4'd4;
        2'b10: trigger_level = 4'd8;
        2'b11: trigger_level = 4'd14;
        endcase
    end

    // ----------------------------------------------------------------
    // Modem Status Register
    // ----------------------------------------------------------------
    reg [3:0] delayed_modem_signals;

    always @(posedge clk) begin
        if (rst) begin
            msr <= 8'b0;
            delayed_modem_signals <= 4'b0;
        end else begin
            msr[`UART_MS_DDCD:`UART_MS_DCTS] <= msi_reset ? 4'b0 :
                msr[`UART_MS_DDCD:`UART_MS_DCTS] | ({dcd, ri, dsr, cts} ^ delayed_modem_signals);
            msr[`UART_MS_CDCD:`UART_MS_CCTS] <= {dcd_c, ri_c, dsr_c, cts_c};
            delayed_modem_signals <= {dcd, ri, dsr, cts};
        end
    end

    // ----------------------------------------------------------------
    // Line Status Register
    // ----------------------------------------------------------------
    wire [7:0] lsr;
    wire lsr0, lsr1, lsr2, lsr3, lsr4, lsr5, lsr6, lsr7;
    reg  lsr0r, lsr1r, lsr2r, lsr3r, lsr4r, lsr5r, lsr6r, lsr7r;

    assign lsr = {lsr7r, lsr6r, lsr5r, lsr4r, lsr3r, lsr2r, lsr1r, lsr0r};

    assign lsr0 = (rf_count == 0) && rf_push_pulse;   // Data Ready
    assign lsr1 = rf_overrun;                           // Overrun Error
    assign lsr2 = rf_data_out[1];                       // Parity Error
    assign lsr3 = rf_data_out[0];                       // Framing Error
    assign lsr4 = rf_data_out[2];                       // Break Interrupt
    assign lsr5 = (tf_count == 5'b0) && thre_set_en;   // TX FIFO Empty (THRE)
    assign lsr6 = (tf_count == 5'b0) && thre_set_en && (tstate == 3'd0);  // Transmitter Empty
    assign lsr7 = rf_error_bit | rf_overrun;            // Error Indicator

    // THRE set enable: simplified (no USART block counter)
    assign thre_set_en = (tstate == 3'd0);   // S_IDLE: THRE only when shift register idle

    // LSR bit 0 (DR) - edge detect
    reg lsr0_d;
    always @(posedge clk)
        if (rst) lsr0_d <= 1'b0;
        else     lsr0_d <= lsr0;

    always @(posedge clk)
        if (rst) lsr0r <= 1'b0;
        else     lsr0r <= ((rf_count == 1) && rf_pop && !rf_push_pulse || rx_reset) ? 1'b0 :
                          lsr0r || (lsr0 && ~lsr0_d);

    // LSR bit 1 (OE) - edge detect
    reg lsr1_d;
    always @(posedge clk)
        if (rst) lsr1_d <= 1'b0;
        else     lsr1_d <= lsr1;

    always @(posedge clk)
        if (rst) lsr1r <= 1'b0;
        else     lsr1r <= lsr_mask ? 1'b0 : lsr1r || (lsr1 && ~lsr1_d);

    // LSR bit 2 (PE) - edge detect
    reg lsr2_d;
    always @(posedge clk)
        if (rst) lsr2_d <= 1'b0;
        else     lsr2_d <= lsr2;

    always @(posedge clk)
        if (rst) lsr2r <= 1'b0;
        else     lsr2r <= lsr_mask ? 1'b0 : lsr2r || (lsr2 && ~lsr2_d);

    // LSR bit 3 (FE) - edge detect
    reg lsr3_d;
    always @(posedge clk)
        if (rst) lsr3_d <= 1'b0;
        else     lsr3_d <= lsr3;

    always @(posedge clk)
        if (rst) lsr3r <= 1'b0;
        else     lsr3r <= lsr_mask ? 1'b0 : lsr3r || (lsr3 && ~lsr3_d);

    // LSR bit 4 (BI) - edge detect
    reg lsr4_d;
    always @(posedge clk)
        if (rst) lsr4_d <= 1'b0;
        else     lsr4_d <= lsr4;

    always @(posedge clk)
        if (rst) lsr4r <= 1'b0;
        else     lsr4r <= lsr_mask ? 1'b0 : lsr4r || (lsr4 && ~lsr4_d);

    // LSR bit 5 (THRE) - level detect, cleared by writing to THR
    reg lsr5_d;
    always @(posedge clk)
        if (rst) lsr5_d <= 1'b1;
        else     lsr5_d <= lsr5;

    always @(posedge clk)
        if (rst) lsr5r <= 1'b1;
        else     lsr5r <= fifo_write ? 1'b0 : lsr5r || (lsr5 && ~lsr5_d);

    // LSR bit 6 (TEMT) - level detect, cleared by writing to THR
    reg lsr6_d;
    always @(posedge clk)
        if (rst) lsr6_d <= 1'b1;
        else     lsr6_d <= lsr6;

    always @(posedge clk)
        if (rst) lsr6r <= 1'b1;
        else     lsr6r <= fifo_write ? 1'b0 : lsr6r || (lsr6 && ~lsr6_d);

    // LSR bit 7 (EI) - edge detect
    reg lsr7_d;
    always @(posedge clk)
        if (rst) lsr7_d <= 1'b0;
        else     lsr7_d <= lsr7;

    always @(posedge clk)
        if (rst) lsr7r <= 1'b0;
        else     lsr7r <= lsr_mask ? 1'b0 : lsr7r || (lsr7 && ~lsr7_d);

    // ----------------------------------------------------------------
    // Divisor Latch Counter (simplified: 16-bit divisor, no M_cnt)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            dlc <= 16'b0;
        end else if (start_dlc | ~(|dlc)) begin
            dlc <= dl - 16'b1;
        end else begin
            dlc <= dlc - 16'b1;
        end
    end

    always @(posedge clk) begin
        if (rst)
            enable <= 1'b0;
        else if (|dl & ~(|dlc))
            enable <= 1'b1;
        else
            enable <= 1'b0;
    end

    // ----------------------------------------------------------------
    // Interrupt Logic
    // ----------------------------------------------------------------
    assign rls_int  = ier[`UART_IE_RLS]  && (lsr[`UART_LS_OE] || lsr[`UART_LS_PE] || lsr[`UART_LS_FE] || lsr[`UART_LS_BI]);
    assign rda_int  = ier[`UART_IE_RDA]  && (rf_count >= {1'b0, trigger_level});
    assign thre_int = ier[`UART_IE_THRE] && lsr[`UART_LS_TFE];
    assign ms_int   = ier[`UART_IE_MS]   && (|msr[3:0]);
    assign ti_int   = ier[`UART_IE_RDA]  && (counter_t == 10'b0) && (|rf_count);

    // Edge detection for interrupt conditions
    reg rls_int_d, rda_int_d, thre_int_d, ms_int_d, ti_int_d;

    always @(posedge clk) begin
        if (rst) begin
            rls_int_d  <= 1'b0;
            rda_int_d  <= 1'b0;
            thre_int_d <= 1'b0;
            ms_int_d   <= 1'b0;
            ti_int_d   <= 1'b0;
        end else begin
            rls_int_d  <= rls_int;
            rda_int_d  <= rda_int;
            thre_int_d <= thre_int;
            ms_int_d   <= ms_int;
            ti_int_d   <= ti_int;
        end
    end

    wire rls_int_rise  = rls_int  & ~rls_int_d;
    wire rda_int_rise  = rda_int  & ~rda_int_d;
    wire thre_int_rise = thre_int & ~thre_int_d;
    wire ms_int_rise   = ms_int   & ~ms_int_d;
    wire ti_int_rise   = ti_int   & ~ti_int_d;

    // Pending interrupt flags (cleared by specific read/write actions)
    reg rls_int_pnd, rda_int_pnd, thre_int_pnd, ms_int_pnd, ti_int_pnd;

    // RLS: cleared by reading LSR
    always @(posedge clk)
        if (rst) rls_int_pnd <= 1'b0;
        else     rls_int_pnd <= lsr_mask ? 1'b0 :
                                  rls_int_rise ? 1'b1 :
                                  rls_int_pnd && ier[`UART_IE_RLS];

    // RDA: cleared when FIFO count drops to trigger level
    reg d1_fifo_read;
    always @(posedge clk) d1_fifo_read <= fifo_read;

    always @(posedge clk)
        if (rst) rda_int_pnd <= 1'b0;
        else     rda_int_pnd <= ((rf_count == {1'b0, trigger_level}) && d1_fifo_read) ? 1'b0 :
                                rda_int_rise ? 1'b1 :
                                rda_int_pnd && ier[`UART_IE_RDA];

    // THRE: cleared by writing to THR or reading IIR when THRE is active
    always @(posedge clk)
        if (rst) thre_int_pnd <= 1'b0;
        else     thre_int_pnd <= (fifo_write || (iir_read & ~iir[`UART_II_IP] & (iir[`UART_II_II] == `UART_II_THRE))) ? 1'b0 :
                                 thre_int_rise ? 1'b1 :
                                 thre_int_pnd && ier[`UART_IE_THRE];

    // MS: cleared by reading MSR
    always @(posedge clk)
        if (rst) ms_int_pnd <= 1'b0;
        else     ms_int_pnd <= msr_read ? 1'b0 :
                               ms_int_rise ? 1'b1 :
                               ms_int_pnd && ier[`UART_IE_MS];

    // TI: cleared by reading RBR
    always @(posedge clk)
        if (rst) ti_int_pnd <= 1'b0;
        else     ti_int_pnd <= fifo_read ? 1'b0 :
                               ti_int_rise ? 1'b1 :
                               ti_int_pnd && ier[`UART_IE_RDA];

    // Interrupt output (priority-encoded)
    always @(posedge clk) begin
        if (rst)
            int_o <= 1'b0;
        else
            int_o <= rls_int_pnd  ? ~lsr_mask  :
                     rda_int_pnd  ? 1'b1        :
                     ti_int_pnd   ? ~fifo_read  :
                     thre_int_pnd ? !(fifo_write & iir_read) :
                     ms_int_pnd   ? ~msr_read   :
                     1'b0;
    end

    // IIR (Interrupt Identification Register)
    always @(posedge clk) begin
        if (rst)
            iir <= 4'b0001;   // No interrupt pending
        else if (rls_int_pnd) begin
            iir[`UART_II_II] <= `UART_II_RLS;
            iir[`UART_II_IP] <= 1'b0;
        end else if (rda_int_pnd) begin
            iir[`UART_II_II] <= `UART_II_RDA;
            iir[`UART_II_IP] <= 1'b0;
        end else if (ti_int_pnd) begin
            iir[`UART_II_II] <= `UART_II_TI;
            iir[`UART_II_IP] <= 1'b0;
        end else if (thre_int_pnd) begin
            iir[`UART_II_II] <= `UART_II_THRE;
            iir[`UART_II_IP] <= 1'b0;
        end else if (ms_int_pnd) begin
            iir[`UART_II_II] <= `UART_II_MS;
            iir[`UART_II_IP] <= 1'b0;
        end else begin
            iir[`UART_II_II] <= 3'b000;
            iir[`UART_II_IP] <= 1'b1;    // No interrupt pending
        end
    end

endmodule
