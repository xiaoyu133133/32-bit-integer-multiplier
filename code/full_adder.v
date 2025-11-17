// full_adder.v
module full_adder(
    input   a,
    input   b,
    input   cin,
    output  sum,
    output  cout
);
    // Sum = a XOR b XOR cin
    assign sum = a ^ b ^ cin;
    
    // Cout = (a AND b) OR (cin AND (a XOR b))
    // Cout = (a & b) | (cin & (a ^ b));
    // 也可以写成：
    assign cout = (a & b) | (a & cin) | (b & cin); 

endmodule