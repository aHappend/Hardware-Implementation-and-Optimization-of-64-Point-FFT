`timescale 1ns/1ps

module tb_fft64_dit_sdf;

    // =========================================================================
    // 1. 参数配置
    // =========================================================================
    parameter integer DATA_WIDTH = 16;
    parameter integer N_POINTS   = 64;
    
    // 输入波形选择: 1: SINE (正弦波, 推荐)
    parameter integer INPUT_MODE = 1; 
    parameter integer WAVE_K = 1; 
    
    // --- 关键调整：减小幅度防止计算过程溢出 ---
    // 原来是 DATA_WIDTH-2 (16384)，现在改为 DATA_WIDTH-3 (8192)
    localparam integer AMP = (1 << (DATA_WIDTH-3)); 

    // =========================================================================
    // 2. 信号声明
    // =========================================================================
    reg clk;
    reg rst_n;
    reg start;

    reg  signed [DATA_WIDTH-1:0] din_real_buf [0:N_POINTS-1];
    reg  signed [DATA_WIDTH-1:0] din_imag_buf [0:N_POINTS-1];
    reg  signed [DATA_WIDTH-1:0] dout_real_buf[0:N_POINTS-1];
    reg  signed [DATA_WIDTH-1:0] dout_imag_buf[0:N_POINTS-1];

    reg  signed [DATA_WIDTH-1:0] dut_din_re, dut_din_im;
    wire signed [DATA_WIDTH-1:0] dut_dout_re, dut_dout_im;
    wire                         dut_valid_out;

    integer i, k;
    integer fout;
    reg capture_done;

    // =========================================================================
    // 3. 实例化 DUT
    // =========================================================================
    fft64_dit_sdf #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .din_re   (dut_din_re),
        .din_im   (dut_din_im),
        .dout_re  (dut_dout_re),
        .dout_im  (dut_dout_im),
        .valid_out(dut_valid_out) 
    );

    // =========================================================================
    // 4. 时钟生成
    // =========================================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================================
    // 5. 输入生成
    // =========================================================================
    function automatic [31:0] my_rand(input [31:0] state);
        my_rand = (1664525 * state + 1013904223);
    endfunction

    task gen_input_data;
        real ang, s;
        integer fin, r, tr, ti;
        reg [31:0] rand_state;
        reg [31:0] rnd_val;
        
        begin
            for(i=0; i<N_POINTS; i++) begin
                din_real_buf[i] = 0; din_imag_buf[i] = 0;
            end

            case (INPUT_MODE)
                0: begin // PULSE
                    din_real_buf[0] = AMP; 
                end
                1: begin // SINE
                    for (i = 0; i < N_POINTS; i++) begin
                        ang = 2.0 * 3.14159265358979 * WAVE_K * i / N_POINTS;
                        s = $sin(ang);
                        din_real_buf[i] = $rtoi(s * AMP);
                    end
                end
                2: begin // SQUARE
                    for (i = 0; i < N_POINTS; i++) begin
                        ang = 2.0 * 3.14159265358979 * WAVE_K * i / N_POINTS;
                        s = $sin(ang);
                        din_real_buf[i] = (s>=0) ? AMP : -AMP;
                    end
                end
                3: begin // RANDOM
                    rand_state = 32'h12345678;
                    for (i = 0; i < N_POINTS; i++) begin
                        rand_state = my_rand(rand_state);
                        rnd_val = rand_state;
                        din_real_buf[i] = $signed(rnd_val[DATA_WIDTH-1:0]) >>> 2;
                        rand_state = my_rand(rand_state);
                        rnd_val = rand_state;
                        din_imag_buf[i] = $signed(rnd_val[DATA_WIDTH-1:0]) >>> 2;
                    end
                end
                4: begin // FILE
                    fin = $fopen("input.txt", "r");
                    if (fin == 0) begin $display("Error: input.txt not found."); $finish; end
                    for (i = 0; i < N_POINTS; i++) begin
                        r = $fscanf(fin, "%d %d\n", tr, ti);
                        din_real_buf[i] = tr; din_imag_buf[i] = ti;
                    end
                    $fclose(fin);
                end
            endcase
        end
    endtask

    // =========================================================================
    // 6. 主控制流程
    // =========================================================================
    initial begin
        rst_n = 0;
        start = 0;
        dut_din_re = 0;
        dut_din_im = 0;
        capture_done = 0;
        
        gen_input_data();

        $display("\n=== INPUT DATA (Full) ===");
        for (i=0; i<N_POINTS; i++)
            $display("x[%0d] = %0d + j%0d", i, din_real_buf[i], din_imag_buf[i]);

        #100;
        rst_n = 1;
        #20;

        $display("\n>>> [Time: %0t] Start feeding data...", $time);
        start = 1;
        
        for (k = 0; k < N_POINTS; k = k + 1) begin
            dut_din_re <= din_real_buf[k];
            dut_din_im <= din_imag_buf[k];
            @(posedge clk);
        end
        
        start <= 0;
        dut_din_re <= 0;
        dut_din_im <= 0;
        $display(">>> [Time: %0t] Feeding done. Waiting for valid_out...", $time);

        fork
            wait(capture_done);
            begin
                #20000; 
                if (!capture_done) begin
                    $display("ERROR: Timeout!");
                    $finish;
                end
            end
        join

        $display("\n=== OUTPUT DATA (Full) ===");
        for (i=0; i<N_POINTS; i++)
            $display("X[%0d] = %0d + j%0d", i, dout_real_buf[i], dout_imag_buf[i]);

        fout = $fopen("output_vivado.txt", "w");
        if (fout) begin
            for (i=0; i<N_POINTS; i++)
                $fwrite(fout, "%d %d\n", dout_real_buf[i], dout_imag_buf[i]);
            $fclose(fout);
            $display("\nSuccess: Written to output_vivado.txt");
        end

        #100;
        $finish;
    end

    // =========================================================================
    // 7. 输出监视器
    // =========================================================================
    integer out_cnt = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_cnt <= 0;
            capture_done <= 0;
        end else begin
            if (dut_valid_out && out_cnt < N_POINTS) begin
                if (out_cnt == 0) 
                    $display(">>> [Time: %0t] Monitor detected valid_out! capturing...", $time);
                dout_real_buf[out_cnt] <= dut_dout_re;
                dout_imag_buf[out_cnt] <= dut_dout_im;
                out_cnt <= out_cnt + 1;
            end
            if (out_cnt == N_POINTS) capture_done <= 1;
        end
    end

endmodule