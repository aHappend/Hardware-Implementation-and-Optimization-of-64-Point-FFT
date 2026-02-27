// sim/tb_fft64.sv
`timescale 1ns/1ps

module tb_fft64;

    // ==============================
    // Parameter configuration
    // ==============================
    parameter integer DATA_WIDTH = 16;
    parameter integer N_POINTS   = 64;
    parameter integer FRAC_BITS  = 15;

    // Input mode
    // 0: PULSE
    // 1: SINE
    // 2: SQUARE
    // 3: RANDOM (LCG, matches Python exactly)
    // 4: FROM_FILE (read from input.txt)
    parameter integer INPUT_MODE = 1;

    // Sine/square cycles (K periods in N points)
    parameter integer WAVE_K = 1;

    // Amplitude in Q format
    localparam integer AMP = (1 << (DATA_WIDTH-3)); // prevent overflow

    // ==============================
    // Signal declarations
    // ==============================
    reg clk;
    reg rst_n;
    reg start;

    reg  signed [DATA_WIDTH-1:0] din_real [0:N_POINTS-1];
    reg  signed [DATA_WIDTH-1:0] din_imag [0:N_POINTS-1];
    wire signed [DATA_WIDTH-1:0] dout_real[0:N_POINTS-1];
    wire signed [DATA_WIDTH-1:0] dout_imag[0:N_POINTS-1];
    wire done;

    // ==============================
    // FFT behavioral model instance
    // ==============================
    fft64_model #(
        .DATA_WIDTH(DATA_WIDTH),
        .N_POINTS  (N_POINTS),
        .FRAC_BITS (FRAC_BITS)
    ) u_fft64 (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .din_real (din_real),
        .din_imag (din_imag),
        .dout_real(dout_real),
        .dout_imag(dout_imag),
        .done     (done)
    );

    // ==============================
    // Clock
    // ==============================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // 100MHz
    end

    integer i;
    integer fin, fout;
    integer r, tmp_real, tmp_imag;

    // ==========================================================
    // LCG random generator, aligned with Python
    // ==========================================================
    function automatic [31:0] my_rand(input [31:0] state);
        my_rand = (1664525 * state + 1013904223);
    endfunction

    // ==========================================================
    // Input generation tasks
    // ==========================================================
    task gen_pulse;
        begin
            for (i = 0; i < N_POINTS; i++) begin
                din_real[i] = (i==0) ? AMP : 0;
                din_imag[i] = 0;
            end
        end
    endtask

    task gen_sine;
        real ang, s;
        begin
            for (i = 0; i < N_POINTS; i++) begin
                ang = 2.0 * 3.14159265358979 * WAVE_K * i / N_POINTS;
                s = $sin(ang);
                din_real[i] = $rtoi(s * AMP);
                din_imag[i] = 0;
            end
        end
    endtask

    task gen_square;
        real ang, s;
        begin
            for (i = 0; i < N_POINTS; i++) begin
                ang = 2.0 * 3.14159265358979 * WAVE_K * i / N_POINTS;
                s = $sin(ang);
                din_real[i] = (s>=0)? AMP : -AMP;
                din_imag[i] = 0;
            end
        end
    endtask

    task gen_random;
        reg [31:0] state;
        reg [31:0] rnd;
        begin
            state = 32'h12345678; // same seed as Python
            for (i = 0; i < N_POINTS; i++) begin
                // real
                state = my_rand(state);
                rnd = state;
                din_real[i] = $signed(rnd[DATA_WIDTH-1:0]);

                // imag
                state = my_rand(state);
                rnd = state;
                din_imag[i] = $signed(rnd[DATA_WIDTH-1:0]);
            end
        end
    endtask

    task gen_from_file;
        begin
            $display("Load input from input.txt");
            
            // From xsim working dir, go up 6 levels back to fft64_sim root
            fin = $fopen("../../../../../../rt1/input.txt", "r");
            if (fin == 0) begin
                $display("ERROR: cannot open input.txt");
                $finish;
            end

            for (i = 0; i < N_POINTS; i++) begin
                r = $fscanf(fin, "%d %d\n", tmp_real, tmp_imag);
                if (r != 2) begin
                    $display("ERROR: bad input format at line %0d", i+1);
                    $finish;
                end
                din_real[i] = tmp_real;
                din_imag[i] = tmp_imag;
            end

            $fclose(fin);
        end
    endtask

    task gen_input_data;
        begin
            case (INPUT_MODE)
                0: gen_pulse();
                1: gen_sine();
                2: gen_square();
                3: gen_random();
                4: gen_from_file();
                default: begin
                    $display("ERROR: wrong INPUT_MODE");
                    $finish;
                end
            endcase
        end
    endtask

    // ==============================
    // Main sequence
    // ==============================
    initial begin
        rst_n = 0;
        start = 0;
        #100;
        rst_n = 1;

        // generate input
        gen_input_data();
        $display("\n=== INPUT DATA ===");
        for (i=0;i<N_POINTS;i++)
            $display("x[%0d] = %0d  %0d", i, din_real[i], din_imag[i]);

        // pulse start
        #20;
        start = 1;
        #10;
        start = 0;

        // wait done
        wait(done==1);
        #20;

        // print outputs
        $display("\n=== OUTPUT FFT DATA ===");
        for (i=0;i<N_POINTS;i++)
            $display("X[%0d] = %0d  %0d", i, dout_real[i], dout_imag[i]);

        // write file (inside xsim directory)
        fout = $fopen("output_vivado.txt", "w");
        if (fout==0) begin
            $display("ERROR: cannot open output_vivado.txt");
            $finish;
        end

        for (i=0;i<N_POINTS;i++)
            $fwrite(fout, "%d %d\n", dout_real[i], dout_imag[i]);
        $fclose(fout);

        $display("\nOutput written to output_vivado.txt");
        #50;
        $finish;
    end

endmodule

