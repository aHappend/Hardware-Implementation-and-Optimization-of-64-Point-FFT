`timescale 1ns/1ps

// =========================================================================
// 模块：复数乘法器 (Complex Multiplier)
// 功能：(ar + j*ai) * (br + j*bi) -> (cr + j*ci)
// 精度：Q1.15 固定点，输出截断回 16 位
// =========================================================================
module cmult #(
    parameter DATA_WIDTH = 16
)(
    input  signed [DATA_WIDTH-1:0] ar, ai,
    input  signed [DATA_WIDTH-1:0] br, bi,
    output signed [DATA_WIDTH-1:0] cr, ci
);
    logic signed [2*DATA_WIDTH:0] p_re, p_im; // 32+1 bit to prevent overflow during add

    // 复数乘法公式:
    // Real: ar*br - ai*bi
    // Imag: ar*bi + ai*br
    
    always_comb begin
        p_re = (ar * br) - (ai * bi);
        p_im = (ar * bi) + (ai * br);
    end

    // 截断：右移 15 位 (Q1.15 * Q1.15 = Q2.30 -> Q1.15)
    // 注意：这里简单截断，实际工程可能需要四舍五入
    assign cr = p_re[DATA_WIDTH + 14 : 15]; 
    assign ci = p_im[DATA_WIDTH + 14 : 15];

endmodule

// =========================================================================
// 模块：蝶形运算单元 (Butterfly Unit)
// 功能：DIT 蝶形，包含缩放 (/2) 以防止溢出
// A' = (A + W*B) >> 1
// B' = (A - W*B) >> 1
// =========================================================================
module butterfly #(
    parameter DATA_WIDTH = 16
)(
    input  signed [DATA_WIDTH-1:0] ar_in, ai_in, // Input A
    input  signed [DATA_WIDTH-1:0] br_in, bi_in, // Input B
    input  signed [DATA_WIDTH-1:0] wr,    wi,    // Twiddle Factor
    output signed [DATA_WIDTH-1:0] ar_out, ai_out,
    output signed [DATA_WIDTH-1:0] br_out, bi_out
);

    wire signed [DATA_WIDTH-1:0] tr, ti; // Temp W*B

    // 实例化复数乘法器计算 W*B
    cmult #(.DATA_WIDTH(DATA_WIDTH)) u_mult (
        .ar(br_in), .ai(bi_in),
        .br(wr),    .bi(wi),
        .cr(tr),    .ci(ti)
    );

    // 蝶形加减 + 缩放 (Shift right by 1)
    assign ar_out = (ar_in + tr) >>> 1;
    assign ai_out = (ai_in + ti) >>> 1;
    assign br_out = (ar_in - tr) >>> 1;
    assign bi_out = (ai_in - ti) >>> 1;

endmodule

// =========================================================================
// 顶层模块：64点流水线 FFT
// =========================================================================
module fft64_model #( // 保持名字为 fft64_model 以兼容 TB，或者并在 TB 中修改实例名
    parameter integer DATA_WIDTH = 16,
    parameter integer N_POINTS   = 64,
    parameter integer FRAC_BITS  = 15
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start,
    
    // 并行输入
    input  wire signed [DATA_WIDTH-1:0]  din_real [0:N_POINTS-1],
    input  wire signed [DATA_WIDTH-1:0]  din_imag [0:N_POINTS-1],

    // 并行输出
    output reg  signed [DATA_WIDTH-1:0]  dout_real [0:N_POINTS-1],
    output reg  signed [DATA_WIDTH-1:0]  dout_imag [0:N_POINTS-1],
    output reg                           done
);

    // ==========================================================
    // 0. 旋转因子查找表 (Look-Up Table for Twiddle Factors)
    //    W_N^k = cos(2pi*k/N) - j*sin(2pi*k/N)
    //    N=64, 需要 k=0 到 31
    // ==========================================================
    function automatic signed [15:0] get_w_real(input integer k);
        case(k)
            0:  get_w_real = 32767;
            1:  get_w_real = 32609;
            2:  get_w_real = 32137;
            3:  get_w_real = 31356;
            4:  get_w_real = 30272;
            5:  get_w_real = 28897;
            6:  get_w_real = 27244;
            7:  get_w_real = 25329;
            8:  get_w_real = 23170;
            9:  get_w_real = 20787;
            10: get_w_real = 18204;
            11: get_w_real = 15446;
            12: get_w_real = 12539;
            13: get_w_real = 9511;
            14: get_w_real = 6392;
            15: get_w_real = 3211;
            16: get_w_real = 0;
            17: get_w_real = -3212;
            18: get_w_real = -6393;
            19: get_w_real = -9512;
            20: get_w_real = -12540;
            21: get_w_real = -15447;
            22: get_w_real = -18205;
            23: get_w_real = -20788;
            24: get_w_real = -23171;
            25: get_w_real = -25330;
            26: get_w_real = -27245;
            27: get_w_real = -28898;
            28: get_w_real = -30273;
            29: get_w_real = -31357;
            30: get_w_real = -32138;
            31: get_w_real = -32610;
            default: get_w_real = 32767;
        endcase
    endfunction

    function automatic signed [15:0] get_w_imag(input integer k);
        case(k)
            0:  get_w_imag = 0;
            1:  get_w_imag = -3212;
            2:  get_w_imag = -6393;
            3:  get_w_imag = -9512;
            4:  get_w_imag = -12540;
            5:  get_w_imag = -15447;
            6:  get_w_imag = -18205;
            7:  get_w_imag = -20788;
            8:  get_w_imag = -23171;
            9:  get_w_imag = -25330;
            10: get_w_imag = -27245;
            11: get_w_imag = -28898;
            12: get_w_imag = -30273;
            13: get_w_imag = -31357;
            14: get_w_imag = -32138;
            15: get_w_imag = -32610;
            16: get_w_imag = -32767;
            17: get_w_imag = -32610;
            18: get_w_imag = -32138;
            19: get_w_imag = -31357;
            20: get_w_imag = -30273;
            21: get_w_imag = -28898;
            22: get_w_imag = -27245;
            23: get_w_imag = -25330;
            24: get_w_imag = -23171;
            25: get_w_imag = -20788;
            26: get_w_imag = -18205;
            27: get_w_imag = -15447;
            28: get_w_imag = -12540;
            29: get_w_imag = -9512;
            30: get_w_imag = -6393;
            31: get_w_imag = -3212;
            default: get_w_imag = 0;
        endcase
    endfunction

    // ==========================================================
    // 1. 信号声明：Pipeline Stages
    //    Stage 0 (Input) -> Stage 1 -> ... -> Stage 6 (Output)
    // ==========================================================
    localparam LOGN = 6;
    
    // 定义每一级的寄存器数组 [Stage][Index]
    reg signed [DATA_WIDTH-1:0] pipe_real [0:LOGN][0:N_POINTS-1];
    reg signed [DATA_WIDTH-1:0] pipe_imag [0:LOGN][0:N_POINTS-1];
    
    // 定义每一级控制信号的流水线
    reg [LOGN:0] valid_pipe;

    // Bit Reversal Wires
    logic [LOGN-1:0] bit_rev_idx;
    integer b, src_idx;

    // ==========================================================
    // 2. Stage 0: 输入加载与位反转 (Bit Reversal)
    // ==========================================================
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_pipe[0] <= 0;
            for(int k=0; k<N_POINTS; k++) begin
                pipe_real[0][k] <= 0;
                pipe_imag[0][k] <= 0;
            end
        end else begin
            valid_pipe[0] <= start; // 捕获 start 脉冲进入流水线
            if (start) begin
                for(int k=0; k<N_POINTS; k++) begin
                    // 计算位反转索引
                    // 简单的 bit-reversal 逻辑 (k=6位)
                    // SystemVerilog 流操作符 {<<{k}} 对于变量索引支持不一
                    // 这里用简单的循环逻辑展开
                    reg [5:0] rev;
                    reg [5:0] orig;
                    orig = k;
                    rev = {orig[0], orig[1], orig[2], orig[3], orig[4], orig[5]};
                    
                    pipe_real[0][rev] <= din_real[k];
                    pipe_imag[0][rev] <= din_imag[k];
                end
            end
        end
    end

    // ==========================================================
    // 3. Stage 1 to 6: 蝶形运算流水线
    //    使用 generate 循环生成每一级的硬件
    // ==========================================================
    genvar s, g, i; // stage, group, butterfly index
    
    generate
        for (s = 1; s <= LOGN; s = s + 1) begin : STAGE_LOOP
            
            // 当前级的参数
            localparam int LEN      = 1 << s;        // 2, 4, 8...
            localparam int HALF_LEN = LEN >> 1;      // 1, 2, 4...
            localparam int NUM_BUTTERFLIES = N_POINTS / 2;

            // 临时线网，连接这一层的计算结果
            wire signed [DATA_WIDTH-1:0] next_real [0:N_POINTS-1];
            wire signed [DATA_WIDTH-1:0] next_imag [0:N_POINTS-1];

            // 生成这一级所有的蝶形单元
            // DIT 循环结构: for i=0 to N step LEN; for j=0 to HALF_LEN
            for (g = 0; g < N_POINTS; g = g + LEN) begin : GROUP_LOOP
                for (i = 0; i < HALF_LEN; i = i + 1) begin : BUTTERFLY_LOOP
                    
                    localparam int idx1 = g + i;
                    localparam int idx2 = g + i + HALF_LEN;
                    
                    // 计算旋转因子索引 Twiddle Index
                    // Twiddle = W_N ^ (i * (N/LEN))
                    // N=64. s=1(Len=2) -> step=32. i=0 -> k=0
                    //       s=2(Len=4) -> step=16. i=0,1 -> k=0,16
                    localparam int k = i * (N_POINTS / LEN);
                    
                    // 获取 LUT 常量
                    wire signed [DATA_WIDTH-1:0] w_r = get_w_real(k);
                    wire signed [DATA_WIDTH-1:0] w_i = get_w_imag(k);

                    // 实例化蝶形单元
                    butterfly #(.DATA_WIDTH(DATA_WIDTH)) u_bf (
                        .ar_in (pipe_real[s-1][idx1]), 
                        .ai_in (pipe_imag[s-1][idx1]),
                        .br_in (pipe_real[s-1][idx2]), 
                        .bi_in (pipe_imag[s-1][idx2]),
                        .wr    (w_r), 
                        .wi    (w_i),
                        .ar_out(next_real[idx1]), 
                        .ai_out(next_imag[idx1]),
                        .br_out(next_real[idx2]), 
                        .bi_out(next_imag[idx2])
                    );
                end
            end

            // 寄存器更新 (流水线级间寄存器)
            always @(posedge clk or negedge rst_n) begin
                if(!rst_n) begin
                    valid_pipe[s] <= 0;
                    for(int m=0; m<N_POINTS; m++) begin
                        pipe_real[s][m] <= 0;
                        pipe_imag[s][m] <= 0;
                    end
                end else begin
                    valid_pipe[s] <= valid_pipe[s-1];
                    // 数据打拍
                    for(int m=0; m<N_POINTS; m++) begin
                        pipe_real[s][m] <= next_real[m];
                        pipe_imag[s][m] <= next_imag[m];
                    end
                end
            end
        end
    endgenerate

    // ==========================================================
    // 4. 输出逻辑
    // ==========================================================
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            done <= 0;
            for(int k=0; k<N_POINTS; k++) begin
                dout_real[k] <= 0;
                dout_imag[k] <= 0;
            end
        end else begin
            done <= valid_pipe[LOGN]; // 最后一级的有效信号
            if (valid_pipe[LOGN]) begin
                for(int k=0; k<N_POINTS; k++) begin
                    dout_real[k] <= pipe_real[LOGN][k];
                    dout_imag[k] <= pipe_imag[LOGN][k];
                end
            end else begin
                done <= 0;
            end
        end
    end

endmodule