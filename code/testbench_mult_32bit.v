// testbench_mult_32bit.v
`timescale 1ns / 1ps

module testbench_mult_32bit;

    // --- 信号定义 ---
    reg  clk;
    reg  reset;
    reg  start;
    reg  signed_mode;
    reg  [31:0] op_a;
    reg  [31:0] op_b;
    wire done;
    wire [63:0] product_out;

    // --- 实例化待测模块 (DUT: Device Under Test) ---
    mult_32bit_no_ops DUT (
        .clk(clk),
        .reset(reset),
        .start(start),
        .signed_mode(signed_mode),
        .op_a(op_a),
        .op_b(op_b),
        .done(done),
        .product_out(product_out)
    );

    // --- 时钟生成 ---
    localparam CLK_PERIOD = 10; // 10ns 周期 (100MHz)
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // --- 任务：运行测试案例 ---
    task run_test;
        input [31:0] A;
        input [31:0] B;
        input mode;
        input [63:0] expected_unsigned; // 预期结果 (无符号表示)
        input [63:0] expected_signed;   // 预期结果 (有符号表示，用于显示)

        reg [63:0] expected_product;
        reg [63:0] check_value;
        reg signed [63:0] signed_result; // 用于显示有符号结果

        begin
            op_a = A;
            op_b = B;
            signed_mode = mode;
            start = 1;
            
            // 根据模式设置预期的检查值
            if (mode == 1'b0) begin // Unsigned
                expected_product = expected_unsigned;
                $display("\n--- Testing UNNSIGNED (%h * %h) ---", A, B);
            end else begin // Signed
                expected_product = expected_unsigned; // 实际硬件输出的无符号表示
                expected_product = expected_signed;   // 仅为方便显示
                $display("\n--- Testing SIGNED (%d * %d) ---", $signed(A), $signed(B));
            end
            
            @(posedge clk);
            start = 0; // 启动后立即拉低 start

            // 等待 'done' 信号
            wait (done);
            
            // 结果检查
            check_value = product_out;
            signed_result = product_out; // 转换为有符号用于显示

            $display("    A  = %h (%d)", A, $signed(A));
            $display("    B  = %h (%d)", B, $signed(B));
            $display("    Mode = %s", mode ? "SIGNED" : "UNSIGNED");
            $display("    Expected Product (Hex): %h", expected_product);
            $display("    Actual Product (Hex):   %h", check_value);
            
            // 使用 $signed() 来显示有符号结果
            if (mode == 1'b1) begin
                $display("    Actual Product (Signed): %d", signed_result);
                $display("    Expected Product (Signed): %d", $signed(expected_signed));
            end

            if (check_value === expected_product) begin
                $display("    *** TEST PASSED ***");
            end else begin
                $display("    !!! TEST FAILED !!!");
                $display("    ERROR: Mismatch between expected (%h) and actual (%h)", expected_product, check_value);
                $finish; // 失败时立即停止仿真
            end
            
            @(posedge clk); // 等待一个周期，确保 done 信号被清除
        end
    endtask

    // --- 主测试序列 ---
    initial begin
        $dumpfile("testbench.vcd");
        $dumpvars(0, testbench_mult_32bit);
        
        // 1. 初始化
        reset = 1;
        start = 0;
        op_a  = 32'b0;
        op_b  = 32'b0;
        @(posedge clk);
        reset = 0;
        $display("--- Reset Complete ---");

        // --- 1. 无符号测试 (SIGNED_MODE = 0) ---
        
        // 1.1 简单乘法: 10 * 20 = 200
        run_test(32'd10, 32'd20, 1'b0, 64'd200, 64'd0);
        
        // 1.2 较大乘法: 32768 * 65536 = 2147483648
        run_test(32'h8000, 32'h10000, 1'b0, 64'h80000000, 64'd0);
        
        // 1.3 边界测试 (最大值 * 最大值): (2^32-1) * (2^32-1)
        // FFFFFFFF * FFFFFFFF = FFFFFFFF00000001
        run_test(32'hFFFF_FFFF, 32'hFFFF_FFFF, 1'b0, 64'hFFFF_FFFE_0000_0001, 64'd0); 
        
        
        // --- 2. 有符号测试 (SIGNED_MODE = 1) ---
        
        // 2.1 正 * 正: 10 * 20 = 200
        run_test(32'd10, 32'd20, 1'b1, 64'd200, 64'd200);

        // 2.2 正 * 负: 10 * (-20) = -200
        // -20 的 32位表示是 FFFFFFEC
        // -200 的 64位表示是 FFFFFFFFFFFF F388
        run_test(32'd10, 32'hFFFF_FFEC, 1'b1, 64'hFFFF_FFFF_FFFF_FF38, 64'hFFFF_FFFF_FFFF_FF38);

        // 2.3 负 * 正: (-10) * 20 = -200
        // -10 的 32位表示是 FFFFFF6
        run_test(32'hFFFF_FFF6, 32'd20, 1'b1, 64'hFFFF_FFFF_FFFF_FF38, 64'hFFFF_FFFF_FFFF_FF38);

        // 2.4 负 * 负: (-10) * (-20) = 200
        run_test(32'hFFFF_FFF6, 32'hFFFF_FFEC, 1'b1, 64'd200, 64'd200);
        
        // 2.5 边界负数: (-1) * (-1) = 1
        // -1 的 32位表示是 FFFFFFFF
        run_test(32'hFFFF_FFFF, 32'hFFFF_FFFF, 1'b1, 64'd1, 64'd1);

        // 2.6 边界负数: (-2^31) * (-1) = 2^31
        // -2^31 的 32位表示是 80000000
        // 2^31 的 64位表示是 00000000 80000000
        run_test(32'h8000_0000, 32'hFFFF_FFFF, 1'b1, 64'h0000_0000_8000_0000, 64'h0000_0000_8000_0000);
        
        // 2.7 边界负数: (-2^31) * (-2^31) = 2^62
        // 80000000 * 80000000 = 40000000 00000000
        run_test(32'h8000_0000, 32'h8000_0000, 1'b1, 64'h4000_0000_0000_0000, 64'h4000_0000_0000_0000);


        // --- 结束仿真 ---
        $display("\n--- All Tests Complete. ---");
        #100;
        $finish;
    end

endmodule