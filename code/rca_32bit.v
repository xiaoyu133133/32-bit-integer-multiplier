// rca_32bit.v - 修正版本

module rca_32bit(
    input  [31:0] a,
    input  [31:0] b,
    input         cin,
    output [31:0] sum,
    output        cout
);

    // 修正：将进位线 c 的范围从 [32:1] 改为 [32:0]，包含 cin
    wire [32:0] c; 
    
    // c[0] 现在是有效的，用于输入进位 cin
    assign c[0] = cin; 

    genvar i;
    // 实例化32个全加器
    generate
        // 循环范围不变 (0 到 31)
        for (i = 0; i < 32; i = i + 1) begin : fa_gen
            full_adder fa_inst (
                .a(a[i]),
                .b(b[i]),
                // 输入进位：使用 c[i]
                .cin(c[i]), 
                .sum(sum[i]),
                // 输出进位：赋值给 c[i+1]
                .cout(c[i+1]) 
            );
        end
    endgenerate

    // cout 是最终进位 c[32]
    assign cout = c[32]; 

endmodule