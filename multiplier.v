module multiplier (input logic [31:0] op1, input logic [31:0] op2, output logic [31:0] result);
	logic [63:0] result_long;
	
	assign result_long = op1 * op2;
	assign result = result_long[31:0];
	
endmodule