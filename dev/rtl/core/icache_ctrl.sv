`timescale 1ns / 1ps

module icache_ctrl(
    input  wire        clk,
    input  wire        reset,

    input  wire        cpu_req_valid,
    input  wire [31:0] cpu_req_addr,
    output wire [31:0] cpu_req_data,
    output wire        cpu_req_ready,

    output wire        mmio_req,
    output wire [31:0] mmio_addr,
    input  wire [31:0] mmio_data,
    input  wire        mmio_valid,

    output wire        refill_req,
    output wire [31:0] refill_addr,
    input  wire [255:0] refill_data,
    input  wire        refill_valid
);

    localparam NUM_SETS  = 8;
    localparam NUM_WAYS  = 4;
    localparam TAG_WIDTH = 7;

    localparam S_IDLE   = 2'd0;
    localparam S_READ   = 2'd1;
    localparam S_REFILL = 2'd2;

    wire is_mmio = ~cpu_req_addr[31];

    wire [TAG_WIDTH-1:0] req_tag  = cpu_req_addr[14:8];
    wire [2:0]            set_idx  = cpu_req_addr[7:5];
    wire [2:0]            word_off = cpu_req_addr[4:2];

    reg [1:0] state;

    reg [7:0] tag_ram [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg [2:0] plru_state [0:NUM_SETS-1];

    wire [7:0] tag_r0 = tag_ram[set_idx][0];
    wire [7:0] tag_r1 = tag_ram[set_idx][1];
    wire [7:0] tag_r2 = tag_ram[set_idx][2];
    wire [7:0] tag_r3 = tag_ram[set_idx][3];

    wire hit0 = tag_r0[7] && (tag_r0[6:0] == req_tag);
    wire hit1 = tag_r1[7] && (tag_r1[6:0] == req_tag);
    wire hit2 = tag_r2[7] && (tag_r2[6:0] == req_tag);
    wire hit3 = tag_r3[7] && (tag_r3[6:0] == req_tag);

    wire cache_hit = hit0 | hit1 | hit2 | hit3;

    wire [1:0] hit_way;
    assign hit_way = hit0 ? 2'd0 :
                     hit1 ? 2'd1 :
                     hit2 ? 2'd2 :
                            2'd3;

    wire inv0 = ~tag_r0[7];
    wire inv1 = ~tag_r1[7];
    wire inv2 = ~tag_r2[7];
    wire inv3 = ~tag_r3[7];

    wire [1:0] plru_victim;
    wire [2:0] plru_next;
    tree_plru u_plru(
        .plru_state (plru_state[set_idx]),
        .victim_way (plru_victim),
        .access_way (hit_way),
        .next_state (plru_next)
    );

    wire [1:0] victim_way = inv0 ? 2'd0 :
                            inv1 ? 2'd1 :
                            inv2 ? 2'd2 :
                                   2'd3;

    reg [2:0]  latched_set;
    reg [1:0]  refill_way;
    reg [31:0] latched_addr;

    wire [4:0] bram_addra = {set_idx, hit_way};
    wire [4:0] bram_addrb = {latched_set, refill_way};

    wire [255:0] bram_douta;
    wire [255:0] bram_doutb;

    wire bram_ena = (state == S_IDLE) && cpu_req_valid && !cpu_req_ready_r && !is_mmio;
    wire bram_enb = refill_valid && (state == S_REFILL);

    icached u_icached(
        .clka   (clk),
        .ena    (bram_ena),
        .wea    (32'b0),
        .addra  (bram_addra),
        .dina   (256'b0),
        .douta  (bram_douta),

        .clkb   (clk),
        .enb    (bram_enb),
        .web    (32'hFFFFFFFF),
        .addrb  (bram_addrb),
        .dinb   (refill_data),
        .doutb  (bram_doutb)
    );

    reg [31:0] bypass_data;

    wire [2:0]   sel_word_off = (state == S_REFILL) ? latched_addr[4:2] : word_off;
    wire [255:0] sel_line     = (state == S_REFILL) ? refill_data : bram_douta;
    wire [31:0]  sel_word;
    assign sel_word = sel_line[sel_word_off*32 +: 32];

    assign cpu_req_data = is_mmio ? mmio_data : bypass_data;

    reg refill_req_r;
    reg [31:0] refill_addr_r;

    assign refill_req  = refill_req_r;
    assign refill_addr = refill_addr_r;

    assign mmio_req  = is_mmio ? cpu_req_valid : 1'b0;
    assign mmio_addr = cpu_req_addr;

    reg cpu_req_ready_r;
    assign cpu_req_ready = cpu_req_ready_r;

    wire [2:0] plru_next_refill;
    tree_plru u_plru_refill(
        .plru_state (plru_state[latched_set]),
        .victim_way (),
        .access_way (refill_way),
        .next_state (plru_next_refill)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state         <= S_IDLE;
            refill_req_r  <= 1'b0;
            refill_addr_r <= 32'b0;
            latched_set   <= 3'b0;
            refill_way    <= 2'b0;
            latched_addr  <= 32'b0;
            bypass_data   <= 32'b0;
            cpu_req_ready_r <= 1'b0;
            for (integer s = 0; s < NUM_SETS; s = s + 1) begin
                plru_state[s] <= 3'b0;
                for (integer w = 0; w < NUM_WAYS; w = w + 1) begin
                    tag_ram[s][w] <= 8'b0;
                end
            end
        end else begin
            cpu_req_ready_r <= 1'b0;

            case (state)
                S_IDLE: begin
                    refill_req_r <= 1'b0;
                    if (cpu_req_valid && !cpu_req_ready_r) begin
                        if (is_mmio) begin
                            if (mmio_valid) begin
                                bypass_data     <= mmio_data;
                                cpu_req_ready_r <= 1'b1;
                            end
                        end else begin
                            state <= S_READ;
                        end
                    end
                end

                S_READ: begin
                    if (cache_hit) begin
                        bypass_data     <= sel_word;
                        cpu_req_ready_r <= 1'b1;
                        plru_state[set_idx] <= plru_next;
                        state <= S_IDLE;
                    end else begin
                        latched_set  <= set_idx;
                        latched_addr <= cpu_req_addr;
                        refill_way   <= victim_way;
                        refill_req_r <= 1'b1;
                        refill_addr_r <= {1'b1, 16'b0, req_tag, set_idx, 5'b0};
                        state <= S_REFILL;
                    end
                end

                S_REFILL: begin
                    refill_req_r <= 1'b1;
                    if (refill_valid) begin
                        refill_req_r    <= 1'b0;
                        bypass_data     <= sel_word;
                        cpu_req_ready_r <= 1'b1;
                        tag_ram[latched_set][refill_way] <= {1'b1, latched_addr[14:8]};
                        plru_state[latched_set] <= plru_next_refill;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
