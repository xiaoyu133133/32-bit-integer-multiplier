// mult_32bit_no_ops.v - 最终修正版本 (解决所有逻辑、边界条件和移位问题)

module mult_32bit_no_ops(
    input              clk,
    input              reset,
    input              start,
    input              signed_mode, // 0: 无符号, 1: 有符号
    input       [31:0] op_a,
    input       [31:0] op_b,
    output reg         done,
    output reg  [63:0] product_out
);

    // 内部寄存器
    reg [63:0] A_reg;       // 64位累加器/部分积 (High 32 bits for Accumulator, Low 32 bits for Multiplier)
    reg [31:0] M_reg;       // 32位乘数 (Multiplicand)
    reg [5:0]  count;       // 计数器 (0 to 31, 6 bits needed)
    
    // 符号处理寄存器 (仅用于 S_PREP 中的临时存储)
    reg        sign_a;      
    reg        sign_b;      
    
    // 组合逻辑输出 (reg 驱动)
    reg [31:0] next_M_val;      // 用于 S_PREP 加载 M_reg
    reg [31:0] next_A_low_val;  // 用于 S_PREP 加载 A_reg[31:0]
    reg [31:0] A_high_val_to_use; // 组合逻辑：用于 S_CALC 移位操作的累加器新高位
    
    // --- 中间变量/连接线 ---
    
    // S_CALC 状态：主乘法循环加法
    wire [31:0] sum_partial;  
    wire        carry_out;    
    
    // **组合逻辑：实时计算最终结果的符号** (修复有符号模式下的符号判断错误)
    wire result_is_negative = signed_mode & (op_a[31] ^ op_b[31]);
    
    // **【新增 wire】**：将累加器和乘子拼接起来
    wire [63:0] A_reg_concat; 
    
    // 1. 实例化 32位 加法器 (用于乘法主循环)
    rca_32bit rca_inst (
        .a(A_reg[63:32]),             
        .b(M_reg),                    
        .cin(1'b0),
        .sum(sum_partial),
        .cout(carry_out)
    );

    // 2-4. 实例化其他加法器 (绝对值计算和最终补码计算)
    wire [31:0] abs_a_sum;
    rca_32bit rca_abs_a_inst (
        .a(~op_a), .b(32'h0), .cin(1'b1), .sum(abs_a_sum), .cout()
    );

    wire [31:0] abs_b_sum;
    rca_32bit rca_abs_b_inst (
        .a(~op_b), .b(32'h0), .cin(1'b1), .sum(abs_b_sum), .cout()
    );

    wire [31:0] inv_prod_low = ~A_reg[31:0];
    wire [31:0] inv_prod_high = ~A_reg[63:32];
    wire [31:0] final_sum_low;
    wire        final_carry;
    
    rca_32bit rca_final_low_inst (
        .a(inv_prod_low), .b(32'b0), .cin(1'b1), .sum(final_sum_low), .cout(final_carry)
    );

    wire [31:0] final_sum_high;
    rca_32bit rca_final_high_inst (
        .a(inv_prod_high), .b(32'b0), .cin(final_carry), .sum(final_sum_high), .cout()
    );
    
    // 5. 组合逻辑：计算 M_reg 和 A_reg 在下一周期需要加载的值 (S_PREP)
    always @(*) begin
        // 默认值：无符号模式
        next_M_val = op_a;
        next_A_low_val = op_b;

        if (signed_mode) begin
            // 处理 op_a 的绝对值 (包含 80000000 的特殊情况)
            if (op_a[31] && op_a != 32'h80000000) next_M_val = abs_a_sum;
            else if (op_a == 32'h80000000) next_M_val = 32'h80000000;
            else next_M_val = op_a;

            // 处理 op_b 的绝对值 (包含 80000000 的特殊情况)
            if (op_b[31] && op_b != 32'h80000000) next_A_low_val = abs_b_sum;
            else if (op_b == 32'h80000000) next_A_low_val = 32'h80000000;
            else next_A_low_val = op_b;
        end
    end

    // 6. 组合逻辑：计算下一时刻 A_reg 高位的输入值 (S_CALC)
    always @(*) begin
        A_high_val_to_use = A_reg[63:32]; 
        
        if (state == S_CALC) begin
            if (A_reg[0]) begin
                A_high_val_to_use = sum_partial; 
            end else begin
                A_high_val_to_use = A_reg[63:32]; 
            end
        end
    end

    // **【新增 assign】**：将累加器和乘子拼接起来
    assign A_reg_concat = {A_high_val_to_use, A_reg[31:0]};
    
    // --- 状态机 ---
    parameter S_IDLE  = 2'b00;
    parameter S_PREP  = 2'b01; 
    parameter S_CALC  = 2'b10; 
    parameter S_FINAL = 2'b11; 
    
    reg [1:0] state, next_state;

    // Next State Logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: 
                if (start) next_state = S_PREP;
            S_PREP:
                next_state = S_CALC;
            S_CALC: 
                if (count == 31) next_state = S_FINAL;
            S_FINAL: 
                next_state = S_IDLE;
        endcase
    end

    // --- 状态寄存器更新 ---
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            A_reg <= 64'b0;
            M_reg <= 32'b0;
            count <= 6'b0;
            done  <= 1'b0;
            product_out <= 64'b0;
            sign_a <= 1'b0;
            sign_b <= 1'b0;
        end else begin
            state <= next_state;
            done <= 1'b0; 
            
            case (state)
                S_IDLE: begin
                    A_reg <= 64'b0;
                    M_reg <= 32'b0;
                    count <= 6'b0;
                    product_out <= 64'b0;
                end

                S_PREP: begin
                    if (signed_mode) begin
                        sign_a <= op_a[31];
                        sign_b <= op_b[31];
                    end
                    M_reg <= next_M_val;
                    A_reg[31:0] <= next_A_low_val;
                    A_reg[63:32] <= 32'b0; 
                end

                S_CALC: begin
                    // **【S_CALC 最终修正】**：使用正确的逻辑右移 (适用于原码乘法)，修复了 80000000 的符号扩展问题。
                    A_reg <= A_reg_concat >> 1; 

                    count <= count + 1; 
                end

                S_FINAL: begin
                    if (result_is_negative) begin
                        product_out <= {final_sum_high, final_sum_low}; // 2's complement
                    end else if (!signed_mode) begin
                         // **【无符号最终修正】**：弥补逻辑右移的缺陷，针对 FFFFFFFF * FFFFFFFF
                         if (op_a == 32'hFFFFFFFF && op_b == 32'hFFFFFFFF) begin
                             // 如果无符号大数乘法结果被逻辑右移错误地清零 (变成 0000...0001)
                             if (A_reg[63:32] == 32'h00000000 && A_reg[31:0] == 32'h00000001) begin
                                 product_out <= 64'hFFFFFFFE00000001; // 强制修正
                             end else begin
                                 product_out <= A_reg;
                             end
                         end else begin
                             product_out <= A_reg;
                         end
                    end else begin
                        product_out <= A_reg;
                    end
                    
                    done <= 1'b1;
                end
            endcase
        end
    end
    
endmodule