// RISC-V PMP (Physical Memory Protection) Checker
//
// Checks physical addresses against 16 PMP entries.
// Produces violation flags for instruction fetch, load, and store accesses.
//
// PMP config format (8 bits per entry):
//   [7]   L   - Lock
//   [6:5] A   - Address matching: 00=OFF, 01=TOR, 10=NA4, 11=NAPOT
//   [4]   X   - Execute permission
//   [3]   W   - Write permission
//   [2]   R   - Read permission
//   [1:0]     - Reserved
//
// Priority: Lower-numbered entries take precedence.
// M-mode bypasses all PMP checks (unlocked AND locked entries).
// No-match defaults: M=allow, S/U=deny.

module pmp_checker (
    input  [31:0] addr,          // Physical address to check
    input  [1:0]  priv_mode,     // Current privilege mode (2'b11=M, 2'b01=S, 2'b00=U)
    input  [1:0]  access_type,   // 00=fetch, 01=load, 10=store

    // PMP CSRs
    input  [31:0] pmpcfg0,  pmpcfg1,  pmpcfg2,  pmpcfg3,
    input  [31:0] pmpaddr0, pmpaddr1, pmpaddr2, pmpaddr3,
    input  [31:0] pmpaddr4, pmpaddr5, pmpaddr6, pmpaddr7,
    input  [31:0] pmpaddr8, pmpaddr9, pmpaddr10, pmpaddr11,
    input  [31:0] pmpaddr12, pmpaddr13, pmpaddr14, pmpaddr15,

    output        violation      // 1 = access denied by PMP
);

    localparam PRIV_M = 2'b11;

    // M-mode always has full access (bypass all PMP checks).
    // This avoids timing issues where priv_mode hasn't updated yet
    // when fetching the trap handler after a trap event.
    assign violation = (priv_mode == PRIV_M) ? 1'b0 : pmp_su_violation;

    // ── S/U-mode PMP check ───────────────────────────────────────────────
    reg pmp_su_violation;

    // Pack PMP config and address into arrays
    wire [7:0]  cfg [0:15];
    wire [31:0] pa  [0:15];

    assign cfg[0]  = pmpcfg0[7:0];    assign pa[0]  = pmpaddr0;
    assign cfg[1]  = pmpcfg0[15:8];   assign pa[1]  = pmpaddr1;
    assign cfg[2]  = pmpcfg0[23:16];  assign pa[2]  = pmpaddr2;
    assign cfg[3]  = pmpcfg0[31:24];  assign pa[3]  = pmpaddr3;
    assign cfg[4]  = pmpcfg1[7:0];    assign pa[4]  = pmpaddr4;
    assign cfg[5]  = pmpcfg1[15:8];   assign pa[5]  = pmpaddr5;
    assign cfg[6]  = pmpcfg1[23:16];  assign pa[6]  = pmpaddr6;
    assign cfg[7]  = pmpcfg1[31:24];  assign pa[7]  = pmpaddr7;
    assign cfg[8]  = pmpcfg2[7:0];    assign pa[8]  = pmpaddr8;
    assign cfg[9]  = pmpcfg2[15:8];   assign pa[9]  = pmpaddr9;
    assign cfg[10] = pmpcfg2[23:16];  assign pa[10] = pmpaddr10;
    assign cfg[11] = pmpcfg2[31:24];  assign pa[11] = pmpaddr11;
    assign cfg[12] = pmpcfg3[7:0];    assign pa[12] = pmpaddr12;
    assign cfg[13] = pmpcfg3[15:8];   assign pa[13] = pmpaddr13;
    assign cfg[14] = pmpcfg3[23:16];  assign pa[14] = pmpaddr14;
    assign cfg[15] = pmpcfg3[31:24];  assign pa[15] = pmpaddr15;

    wire [15:0] entry_match;
    wire [15:0] entry_allow;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin: pmp_entry
            wire [1:0]  a_mode = cfg[i][6:5];
            wire        perm_x = cfg[i][4];
            wire        perm_w = cfg[i][3];
            wire        perm_r = cfg[i][2];

            // TOR addresses (shifted left by 2 to form physical address)
            wire [31:0] tor_top  = {pa[i][29:0], 2'b00};
            wire [31:0] tor_base = (i == 0) ? 32'h0 :
                                   {pa[i-1][29:0], 2'b00};

            // NA4: 4-byte naturally aligned
            wire na4_match = (addr[31:2] == pa[i][29:0]);

            // NAPOT: power-of-two naturally aligned
            wire [31:0] xor_val    = pa[i] ^ (pa[i] + 1'b1);
            wire [31:0] napot_mask = (xor_val << 2) | 32'h3;
            wire [31:0] napot_base = {pa[i][29:0], 2'b00} & ~napot_mask;
            wire        napot_match = ((addr & ~napot_mask) == napot_base);

            // Address match based on A mode
            assign entry_match[i] = (a_mode == 2'b00) ? 1'b0 :
                                    (a_mode == 2'b01) ? (addr >= tor_base && addr < tor_top) :
                                    (a_mode == 2'b10) ? na4_match :
                                                         napot_match;

            // Permission check
            wire perm_ok = (access_type == 2'b00) ? perm_x :
                           (access_type == 2'b01) ? perm_r :
                                                     perm_w;

            assign entry_allow[i] = !entry_match[i] || perm_ok;
        end
    endgenerate

    // Priority encoder: find first matching entry
    reg        any_match;
    reg        first_match_allow;

    integer j;
    always @(*) begin
        any_match         = 1'b0;
        first_match_allow = 1'b1;

        for (j = 0; j < 16; j = j + 1) begin
            if (!any_match && entry_match[j]) begin
                any_match         = 1'b1;
                first_match_allow = entry_allow[j];
            end
        end

        // Matched entry: use entry decision
        // No match: S/U denied (default deny for S/U per RISC-V spec)
        pmp_su_violation = any_match ? !first_match_allow : 1'b1;
    end

endmodule
