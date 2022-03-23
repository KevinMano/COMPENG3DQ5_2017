`timescale 1ns/100ps
`default_nettype none

//Kevin Mano 
//24th November 2017
//This is the variable shifter module that is required for Milestone 3. 

module variable_shifter2 (
	input logic clock,
	input logic resetn,
	input logic enable,								//Milestone 3 enables this module. If this is 0, do not read info.
	input logic quantization_matrix,				//0 if Q0 is used, and 1 if Q1 is used.
	input logic [8:0] input_bits,					//Input is 9 bits.
	output logic [15:0] result,					//Output is 16 bits, we do the shifting.	
	output logic wren_a,
	output logic [7:0] address_a
);

//Other parts needed for this module.
logic [3:0] diagonal_index;						//Based on different values of diagonal_index, we will shift the number differently.
logic [6:0] element_count_index; 				//The element_count_index tracks how many numbers you have scanned from the matrix.
logic [2:0] shift_code;				
logic first_in_line;									//The first_in_line flag checks if its the first write on the diagonal, if it is, don't increment the limits yet.
logic passed_leading_diagonal; 					//If this flag is 1, then we have to 

//Registers needed for writing to the RAM. 
logic [2:0] RAM_column_index;
logic [2:0] RAM_row_index;
logic [2:0] RAM_row_limit;
logic [2:0] RAM_column_limit;
logic direction;									  //If this is 1, our scan pattern is going diagonally up. If this is 0, the scan pattern is going diagonally down.
//logic diagonal_limit;							  //Use this after you pass the leading diagonal. 


assign diagonal_index = address_a[2:0] + address_a[5:3];//RAM_row_index + RAM_column_index;
assign address_a = {2'b00, RAM_row_index, RAM_column_index};
assign wren_a = enable;

always_comb begin	
	if(quantization_matrix == 1'b0) begin					//Q0 quantization_matrix
		if(diagonal_index == 4'd0) begin
			shift_code = 3'b011;
		end else if(diagonal_index == 4'd1) begin
			shift_code = 3'b010;
		end else if(diagonal_index <= 4'd3) begin
			shift_code = 3'b011;
		end else if(diagonal_index <= 4'd5) begin
			shift_code = 3'b100;
		end else if(diagonal_index <= 4'd7) begin
			shift_code = 3'b101;
		end else begin
			shift_code = 3'b110;
		end
	end else begin													//Q1 quantization_matrix
		if(diagonal_index == 4'd0) begin
			shift_code = 3'b011;
		end else if(diagonal_index == 4'd1) begin
			shift_code = 3'b001;
		end else if(diagonal_index <= 4'd3) begin
			shift_code = 3'b001;
		end else if(diagonal_index <= 4'd5) begin
			shift_code = 3'b010;
		end else if(diagonal_index <= 4'd7) begin
			shift_code = 3'b011;
		end else if(diagonal_index <= 4'd10) begin
			shift_code = 3'b100;
		end else begin
			shift_code = 3'b101;
		end
	end
	
	case(shift_code)
		3'b001: begin														//Multiply by 2
			result = {{6{input_bits[8]}},input_bits,1'b0};
		end
		
		3'b010: begin														//Multiply by 4.
			result = {{5{input_bits[8]}},input_bits,2'b0};
		end
		
		3'b011: begin														//Multiply by 8.
			result = {{4{input_bits[8]}},input_bits,3'b0};
		end
		
		3'b100: begin														//Multiply by 16.			
			result = {{3{input_bits[8]}},input_bits,4'b0};
		end
		
		3'b101: begin														//Multiply by 32.
			result = {{2{input_bits[8]}},input_bits,5'b0};
		end
		
		3'b110: begin														//Multiply by 64.
			result = {input_bits[8],input_bits,6'b0};
		end
		
		default: shift_code = 3'b010;
		
	endcase
end

always_ff @(posedge clock or negedge resetn) begin
	if(resetn == 1'b0) begin
		element_count_index <= 7'd0;
		RAM_column_index <= 3'd0;
		RAM_row_index <= 3'd0;
		RAM_column_limit <= 3'd1;
		RAM_row_limit <= 3'd1;
		direction <= 1'b0;
		first_in_line <= 1'b0;
		passed_leading_diagonal <= 1'b0;
	end else begin
		if(enable == 1'b1) begin													//Signal asserted by milestone3 module. 
			element_count_index <= 7'd0;
			if(element_count_index == 7'd63) begin								//Not reached the end of the matrix.
				element_count_index <= 7'd0;
				direction <= 1'b0;
				RAM_column_limit <= 3'd1;
				RAM_column_index <= 3'd0;
				RAM_row_limit <= 3'd1;
				RAM_row_index <= 3'd0;
				first_in_line <= 1'b0;
				passed_leading_diagonal <= 1'b0;
			end else if(element_count_index == 7'd0) begin					//The first element is slightly different.
				RAM_column_index <= RAM_column_index + 3'd1;
				first_in_line <= 1'b1;
				element_count_index <= element_count_index + 7'd1;			//We increment the element_count_index.
			end  else if(element_count_index == 7'd62) begin
				RAM_column_index <= RAM_column_index + 3'd1;
				element_count_index <= element_count_index + 7'd1;
			end else begin
				element_count_index <= element_count_index + 7'd1;			//We increment the element_count_index.
				if(RAM_column_index == RAM_column_limit) begin				//We are at the end of the column for the scan. This can only happen at the "top" of the matrix.
					if(passed_leading_diagonal == 1'b0) begin
						if(first_in_line == 1'b1) begin							//This happened the first time in this diagonal, you want to go diagonally, not right/down.
							RAM_column_index <= RAM_column_index - 3'd1;
							RAM_row_index <= RAM_row_index + 3'd1;
							first_in_line <= 1'b0;
						end else begin
							RAM_column_index <= RAM_column_index + 3'd1;		//Then the only place you can go is right. You cannot go down. 
							RAM_column_limit <= RAM_column_limit + 3'd1;		//You also have to increment the row and column scanning boundaries.
							RAM_row_limit <= RAM_row_limit + 3'd1;
							direction <= 1'b0;
							first_in_line <= 1'b1;
						end
					end else begin														//You have passed_leading_diagonal now.
						if(first_in_line == 1'b1) begin							//This happened the first time in this diagonal, you want to go diagonally, not right/down.
							RAM_column_index <= RAM_column_index - 3'd1;
							RAM_row_index <= RAM_row_index + 3'd1;
							first_in_line <= 1'b0;
						end else begin
							RAM_row_index <= RAM_row_index + 3'd1;				//Then the only place you can go is right. You cannot go down. 
							RAM_column_limit <= RAM_column_limit - 3'd1;		//You also have to increment the row and column scanning boundaries.
							RAM_row_limit <= 3'd7;//RAM_row_limit - 3'd1;
							direction <= 1'b0;
							first_in_line <= 1'b1;
						end
					end
				end else if(RAM_row_index == RAM_row_limit) begin			//We are at the end of the row for the scan. This can only happen at the "bottom" of the matrix.
					if(passed_leading_diagonal == 1'b0) begin					//You have not passed_leading_diagonal yet.
						if(first_in_line == 1'b1) begin							//This happened the first time in this diagonal, you want to go diagonally, not right/down.
							RAM_column_index <= RAM_column_index + 3'd1;
							RAM_row_index <= RAM_row_index - 3'd1;
							first_in_line <= 1'b0;
						end else begin
							RAM_row_index <= RAM_row_index + 3'd1;				//Then the only place you can go is down. You cannot go right.
							RAM_column_limit <= RAM_column_limit + 3'd1;		//You also have to increment the row and column scanning boundaries.
							RAM_row_limit <= RAM_row_limit + 3'd1;
							direction <= 1'b1;										//Now you have to go the other way... diagonally up.
							first_in_line <= 1'b1;									//Ensure that this doesn't repeat. 
						end
					end else begin														//You have passed_leading_diagonal now...
						if(first_in_line == 1'b1) begin							//This happened the first time in this diagonal, you want to go diagonally, not right/down.
							RAM_column_index <= RAM_column_index + 3'd1;
							RAM_row_index <= RAM_row_index - 3'd1;
							first_in_line <= 1'b0;
						end else begin
							RAM_column_index <= RAM_column_index + 3'd1;		//Then the only place you can go is down. You cannot go right.
							RAM_column_limit <= 3'd7;//RAM_column_limit - 3'd1;		//You also have to increment the row and column scanning boundaries.
							RAM_row_limit <= RAM_row_limit - 3'd1;
							direction <= 1'b1;										//Now you have to go the other way... diagonally up.
							first_in_line <= 1'b1;									//Ensure that this doesn't repeat. 
						end
					end
				end else begin															//You haven't reached the scanning boundaries yet. So you increment one and decrement the other, depending on the direction flag.
					if(direction == 1'b0) begin									//Your direction is diagonally down. 
						RAM_column_index <= RAM_column_index - 3'd1;
						RAM_row_index <= RAM_row_index + 3'd1;
					end else begin														//Your direction is diagonally up.
						RAM_column_index <= RAM_column_index + 3'd1;
						RAM_row_index <= RAM_row_index - 3'd1;
					end
				end
			end																			
		end
		
		if((RAM_column_limit == 3'd7) && (first_in_line == 1'b0)) begin	//The condition to assert passed_leading_diagonal.
			passed_leading_diagonal <= 1'b1;
		end
	end
end


endmodule