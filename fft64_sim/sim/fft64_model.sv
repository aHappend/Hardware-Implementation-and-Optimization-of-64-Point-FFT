`timescale 1ns/1ps

// =========================================================================
// 1. 旋转因子 ROM
// =========================================================================
module twiddle_rom_64 #(parameter DATA_WIDTH=16) (
    input  wire [5:0] addr,
    output reg signed [DATA_WIDTH-1:0] w_re,
    output reg signed [DATA_WIDTH-1:0] w_im
);
    always_comb begin
        case(addr)
            6'd0 : begin w_re =  32767; w_im =      0; end
            6'd1 : begin w_re =  32609; w_im =  -3212; end
            6'd2 : begin w_re =  32137; w_im =  -6393; end
            6'd3 : begin w_re =  31356; w_im =  -9512; end
            6'd4 : begin w_re =  30273; w_im = -12539; end
            6'd5 : begin w_re =  28898; w_im = -15446; end
            6'd6 : begin w_re =  27245; w_im = -18204; end
            6'd7 : begin w_re =  25329; w_im = -20787; end
            6'd8 : begin w_re =  23170; w_im = -23170; end
            6'd9 : begin w_re =  20787; w_im = -25329; end
            6'd10: begin w_re =  18204; w_im = -27245; end
            6'd11: begin w_re =  15446; w_im = -28898; end
            6'd12: begin w_re =  12539; w_im = -30273; end
            6'd13: begin w_re =   9512; w_im = -31356; end
            6'd14: begin w_re =   6393; w_im = -32137; end
            6'd15: begin w_re =   3212; w_im = -32609; end
            6'd16: begin w_re =      0; w_im = -32767; end
            6'd17: begin w_re =  -3212; w_im = -32609; end
            6'd18: begin w_re =  -6393; w_im = -32137; end
            6'd19: begin w_re =  -9512; w_im = -31356; end
            6'd20: begin w_re = -12539; w_im = -30273; end
            6'd21: begin w_re = -15446; w_im = -28898; end
            6'd22: begin w_re = -18204; w_im = -27245; end
            6'd23: begin w_re = -20787; w_im = -25329; end
            6'd24: begin w_re = -23170; w_im = -23170; end
            6'd25: begin w_re = -25329; w_im = -20787; end
            6'd26: begin w_re = -27245; w_im = -18204; end
            6'd27: begin w_re = -28898; w_im = -15446; end
            6'd28: begin w_re = -30273; w_im = -12539; end
            6'd29: begin w_re = -31356; w_im =  -9512; end
            6'd30: begin w_re = -32137; w_im =  -6393; end
            6'd31: begin w_re = -32609; w_im =  -3212; end
            default: begin w_re = 32767; w_im = 0; end
        endcase
    end
endmodule

// =========================================================================
// 2. 复数乘法器
// =========================================================================
module cmult_std #(parameter DATA_WIDTH=16)(
    input  signed [DATA_WIDTH-1:0] ar, ai,
    input  signed [DATA_WIDTH-1:0] br, bi,
    output signed [DATA_WIDTH-1:0] cr, ci
);
    logic signed [2*DATA_WIDTH:0] p_re, p_im;
    always_comb begin
        p_re = ar * br - ai * bi;
        p_im = ar * bi + ai * br;
    end
    assign cr = p_re[DATA_WIDTH + 14 : 15]; 
    assign ci = p_im[DATA_WIDTH + 14 : 15];
endmodule

// =========================================================================
// 3. 输入位反转 Buffer
// =========================================================================
module input_reorder_buffer #(parameter DATA_WIDTH=16)(
    input  wire clk, rst_n, start,
    input  wire signed [DATA_WIDTH-1:0] din_re, din_im,
    output reg  signed [DATA_WIDTH-1:0] dout_re, dout_im,
    output reg  valid_out
);
    reg signed [DATA_WIDTH-1:0] mem_re [0:127];
    reg signed [DATA_WIDTH-1:0] mem_im [0:127];
    reg [6:0] wr_cnt;
    reg [6:0] rd_cnt;
    reg filling;

    function [5:0] bit_rev(input [5:0] in);
        bit_rev = {in[0], in[1], in[2], in[3], in[4], in[5]};
    endfunction

    wire bank_sel_wr = wr_cnt[6];
    wire [5:0] addr_wr = wr_cnt[5:0]; 
    wire bank_sel_rd = ~wr_cnt[6];
    wire [5:0] addr_rd = bit_rev(rd_cnt[5:0]); 

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_cnt <= 0; rd_cnt <= 0; valid_out <= 0; filling <= 1;
        end else begin
            if (start || !filling) begin
                mem_re[{bank_sel_wr, addr_wr}] <= din_re;
                mem_im[{bank_sel_wr, addr_wr}] <= din_im;
                wr_cnt <= wr_cnt + 1;
                if(filling && wr_cnt==63) filling <= 0;
            end else if (!filling && wr_cnt == rd_cnt) begin
                valid_out <= 0;
            end
            
            if (!filling) begin
                valid_out <= 1;
                dout_re <= mem_re[{bank_sel_rd, addr_rd}];
                dout_im <= mem_im[{bank_sel_rd, addr_rd}];
                rd_cnt <= rd_cnt + 1;
            end
        end
    end
endmodule

// =========================================================================
// 4. DIT SDF Stage (核心 DIT 级)
//    修复：解决了 DELAY_LEN=1 时 part-select [-1:0] 的报错
// =========================================================================
module dit_sdf_stage #(
    parameter DATA_WIDTH = 16,
    parameter DELAY_LEN  = 1,
    parameter STAGE_ID   = 0
)(
    input  wire clk, rst_n, 
    input  wire en_in, 
    input  wire signed [DATA_WIDTH-1:0] din_re, din_im,
    
    output reg  en_out, 
    output reg  signed [DATA_WIDTH-1:0] dout_re, dout_im
);
    reg signed [DATA_WIDTH-1:0] fifo_re [0:DELAY_LEN-1];
    reg signed [DATA_WIDTH-1:0] fifo_im [0:DELAY_LEN-1];
    
    reg [5:0] local_cnt;
    
    wire signed [DATA_WIDTH-1:0] mult_re, mult_im;
    logic signed [DATA_WIDTH:0] sum_re, sum_im, sub_re, sub_im;
    wire signed [DATA_WIDTH-1:0] bf_a_re, bf_a_im; 
    wire signed [DATA_WIDTH-1:0] bf_b_re, bf_b_im; 
    
    wire signed [DATA_WIDTH-1:0] fifo_out_re = fifo_re[DELAY_LEN-1];
    wire signed [DATA_WIDTH-1:0] fifo_out_im = fifo_im[DELAY_LEN-1];

    wire control = (local_cnt & DELAY_LEN) ? 1'b1 : 1'b0;

    wire [5:0] tw_idx;
    wire [5:0] delay_mask = DELAY_LEN - 1;
    assign tw_idx = (local_cnt & delay_mask) << (5 - STAGE_ID);

    wire signed [DATA_WIDTH-1:0] w_r, w_i;
    twiddle_rom_64 #(.DATA_WIDTH(DATA_WIDTH)) u_rom (.addr(tw_idx), .w_re(w_r), .w_im(w_i));

    cmult_std #(.DATA_WIDTH(DATA_WIDTH)) u_mult (
        .ar(din_re), .ai(din_im), .br(w_r), .bi(w_i),
        .cr(mult_re), .ci(mult_im)
    );

    always_comb begin
        sum_re = fifo_out_re + mult_re;
        sum_im = fifo_out_im + mult_im;
        sub_re = fifo_out_re - mult_re;
        sub_im = fifo_out_im - mult_im;
    end
    assign bf_a_re = sum_re[DATA_WIDTH:1]; 
    assign bf_a_im = sum_im[DATA_WIDTH:1];
    assign bf_b_re = sub_re[DATA_WIDTH:1]; 
    assign bf_b_im = sub_im[DATA_WIDTH:1];

    reg [DELAY_LEN-1:0] delay_line_en;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for(i=0; i<DELAY_LEN; i++) begin fifo_re[i]<=0; fifo_im[i]<=0; end
            dout_re <= 0; dout_im <= 0;
            local_cnt <= 0;
            delay_line_en <= 0;
            en_out <= 0;
        end else begin
            // --- 修复点：增加条件判断，防止出现负数索引 ---
            if (DELAY_LEN == 1) begin
                delay_line_en <= en_in;
            end else begin
                delay_line_en <= {delay_line_en[DELAY_LEN-2:0], en_in};
            end
            en_out <= delay_line_en[DELAY_LEN-1];
            // ------------------------------------------

            if (en_in) begin
                local_cnt <= local_cnt + 1;
                
                for(i=DELAY_LEN-1; i>0; i--) begin
                    fifo_re[i] <= fifo_re[i-1];
                    fifo_im[i] <= fifo_im[i-1];
                end
                
                if (control == 1'b0) begin 
                    fifo_re[0] <= din_re;
                    fifo_im[0] <= din_im;
                    dout_re    <= fifo_out_re; 
                    dout_im    <= fifo_out_im;
                end else begin
                    dout_re    <= bf_a_re;
                    dout_im    <= bf_a_im;
                    fifo_re[0] <= bf_b_re;
                    fifo_im[0] <= bf_b_im;
                end
            end
        end
    end
endmodule

// =========================================================================
// 5. 顶层模块 (DIT Version)
// =========================================================================
module fft64_dit_sdf #(
    parameter DATA_WIDTH = 16
)(
    input  wire clk, rst_n, start,
    input  wire signed [DATA_WIDTH-1:0] din_re, din_im,
    output wire signed [DATA_WIDTH-1:0] dout_re, dout_im,
    output wire valid_out
);
    wire signed [DATA_WIDTH-1:0] stg_re [0:6];
    wire signed [DATA_WIDTH-1:0] stg_im [0:6];
    wire en_chain [0:6];
    
    input_reorder_buffer #(.DATA_WIDTH(DATA_WIDTH)) u_in_buf (
        .clk(clk), .rst_n(rst_n), .start(start),
        .din_re(din_re), .din_im(din_im),
        .dout_re(stg_re[0]), .dout_im(stg_im[0]),
        .valid_out(en_chain[0])
    );

    genvar s;
    generate
        for(s=0; s<6; s=s+1) begin : DIT_STAGES
            localparam int DELAY = 1 << s; 
            
            dit_sdf_stage #(
                .DATA_WIDTH(DATA_WIDTH), 
                .DELAY_LEN(DELAY),
                .STAGE_ID(s)
            ) u_stg (
                .clk(clk), 
                .rst_n(rst_n), 
                .en_in(en_chain[s]),     
                .din_re(stg_re[s]), 
                .din_im(stg_im[s]), 
                .en_out(en_chain[s+1]),  
                .dout_re(stg_re[s+1]), 
                .dout_im(stg_im[s+1])
            );
        end
    endgenerate

    assign dout_re = stg_re[6];
    assign dout_im = stg_im[6];
    assign valid_out = en_chain[6];

endmodule