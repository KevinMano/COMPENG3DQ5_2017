`timescale 1ns/100ps
`default_nettype none

//20th November 2017
//This module is implemented for address generation for milestone 2.
//It consists of modulo counters to figure out which row, column and matrix we are in.
//Takes as input whether it is a fetch or write cycle, and generates 64 addresses based on what matrix number we are in.
//Bear in mind that for U and V, these matrices are downsampled, so there are half as many matrices as there are for Y.

module address_generator (
		input logic clock,	                     // 50 MHz clock
		input logic resetn,								//Reset_n signal
		input logic fetch_address_enable,			//1 if we are fetching data, 0 if we are writing data.
		input logic write_address_enable,			//To make sure we don't automatically generate write addresses if we are not fetching.
		output logic [17:0] address,					//Address that is generated.
		output logic [7:0] RAM_address,
		output logic DP_RAM,
		output logic done,									//A bit to signal completion of the fetch/write cycle.
		input logic first_cycle
);

//Parameters for the different offsets.
//If we write consecutively, and use different registers, we don't need the offsets, because the locations are continuous.
parameter FETCH_OFFSET = 18'd76800,					// Location of the start of the S' values
			 U_OFFSET = 18'd38400,						// Offset for the Post IDCT U values.
			 V_OFFSET = 18'd57600;						// Offset for the Post IDCT V values.

//For row addressing
//logic [17:0] row_count;									//Counts the number of rows.
logic [17:0] write_row_count;							//13 bits because the biggest number is 2240 

//For matrix offsetting
//logic [5:0] matrix_count;								//Count how many matrices. (max 39 matrices before we go to the next block.
//logic [17:0] matrix_offset;							//Matrix width offset.
logic [6:0] write_matrix_count;
logic [17:0] write_matrix_offset;
//logic [12:0] row_comparator;							//For the UV fetching.
//logic [12:0] row_increment;
//logic [17:0] matrix_increment;
logic [12:0] write_row_comparator;					//For the UV fetching.
logic [12:0] write_row_increment;
logic [17:0] write_matrix_increment;
//logic [17:0] matrix_comparator;
logic [17:0] write_matrix_comparator;

//For column addressing.
//logic [2:0] column_count;								//Counts the number of columns
logic [2:0] write_column_count;

//For element fetch/write limits.
logic [6:0] fetch_element_count;						//Counts the number of elements we have read.
logic [5:0] write_element_count;						//Counts the number of elements we have written.

//To make sure timing for reads and writes is correct. 
logic one_more_read;
logic one_more_write;

//logic DP_RAM; 
//logic fetch_UV;
logic write_UV;

//assign row_comparator =   (fetch_UV == 1'b1) ? 13'd1120 : 13'd2240;
//assign row_increment =    (fetch_UV == 1'b0) ? 13'd320 : 13'd160;
//assign matrix_increment = (fetch_UV == 1'b1) ? 18'd1128 : 18'd2248;
//assign matrix_comparator = (fetch_UV == 1'b1) ? 18'd19 : 18'd39;

assign write_row_comparator =   (write_UV == 1'b1) ? 13'd560 : 13'd1120;
assign write_row_increment =    (write_UV == 1'b0) ? 13'd160 : 13'd80;
assign write_matrix_increment = (write_UV == 1'b1) ? 18'd564 : 18'd1124;
assign write_matrix_comparator = (write_UV == 1'b1) ? 18'd19 : 18'd39;

always_ff @(posedge clock or negedge resetn) begin	
	if(~resetn) begin
//		column_count <= 3'd0;	
//		row_count <= 13'd0;
		write_row_count <= 13'd0;
		write_column_count <= 3'd0;
		write_matrix_count <= 7'd0;
		write_matrix_offset <= 18'd0;
		fetch_element_count <= 7'd0;
		write_element_count <= 6'd0;
//		matrix_count <= 6'd0;
//		matrix_offset <= 18'd0;
		done <= 1'b0;
		one_more_read <= 1'b0;
		one_more_write <= 1'b0;
//		fetch_UV <= 1'b0;
		write_UV <= 1'b0;
		DP_RAM <= 1'b0;
		RAM_address <= 8'd0;
		address <= 18'd0;
	end else begin
		if (first_cycle == 1'b1) begin
//			column_count <= 3'd0;
//			row_count <= 13'd0;
			write_row_count <= 13'd0;
			write_column_count <= 3'd0;
			write_matrix_count <= 7'd0;
			write_matrix_offset <= 18'd0;
			fetch_element_count <= 7'd0;
			write_element_count <= 6'd0;
//			matrix_count <= 6'd0;
//			matrix_offset <= 18'd0;
			done <= 1'b0;
			one_more_read <= 1'b0;
			one_more_write <= 1'b0;
//			fetch_UV <= 1'b0;
			write_UV <= 1'b0;
			RAM_address <= 8'd0;
			address <= 18'd0;
			DP_RAM <= 1'b0;
		end
		if(fetch_address_enable || one_more_read) begin									//If we want to fetch data from the SRAM.
			one_more_read <= 1'b1;
			done <= 1'b0;
			DP_RAM <= 1'b1;
			if(fetch_element_count < 7'd64) begin											//While we haven't fetched 64 values.
		//		if(fetch_element_count == 7'd0 && matrix_offset == 13'd0) begin
		//			column_count <= 3'd0;
		//			row_count <= 13'd0;
		//		end else begin
/*					if(column_count == 3'd7) begin											//Reached the end of the row.
						if(row_count == row_comparator) begin										//We are at the end of a matrix
							if(matrix_count == matrix_comparator) begin									//We are at the end of the row for matrices.
								matrix_count <= 6'd0;		
								matrix_offset <= matrix_offset + matrix_increment;				//Go to the next row block.
							end else begin
								matrix_count <= matrix_count + 6'd1;
								matrix_offset <= matrix_offset + 18'd8;
							end
							row_count <= 3'd0;
						end else begin
							row_count <= row_count + row_increment;								//First element in the next row.
						end
						column_count <= 3'd0;													//Reset the column_count, increment the row_count.
					end else begin
						column_count <= column_count + 3'd1;
					end*/
		//		end
				fetch_element_count <= fetch_element_count + 7'd1;
			//end else if(fetch_element_count < 7'd65) begin
			//	fetch_element_count <= fetch_element_count + 7'd1;
			end else begin
				done <= 1'b1;
				one_more_read <= 1'b0;
			end
			
//			address <= FETCH_OFFSET + row_count + column_count + matrix_offset;
//			if (address > 18'd153600) begin
//				fetch_UV <= 1'b1;
//			end
			RAM_address <= fetch_element_count;
		end else if(write_address_enable == 1'b1 || one_more_write) begin
			one_more_write <= 1'b1;
			done <= 1'b0;
			if(write_element_count < 6'd32) begin							//While we haven't written 64 (32 pairs of) values.
//				if(write_element_count == 6'd0 && write_matrix_offset == 13'd0) begin
//					write_column_count <= 3'd0;
//					write_row_count <= 13'd0;
//				end else begin
					if(write_column_count == 3'd3) begin						//Reached the end of the row.
						if(write_row_count == write_row_comparator) begin		
							if(write_matrix_count == write_matrix_comparator) begin
								write_matrix_count <= 7'd0;
								write_matrix_offset <= write_matrix_offset + write_matrix_increment;
							end else begin
								write_matrix_count <= write_matrix_count + 7'd1;
								write_matrix_offset <= write_matrix_offset + 18'd4;
							end
							write_row_count <= 13'd0;
						end else begin
							write_row_count <= write_row_count + write_row_increment;		//Increment the row_count.
						end
						write_column_count <= 3'd0;								//Reset the column_count.
					end else begin
						write_column_count <= write_column_count + 3'd1;
					end
//				end
				write_element_count <= write_element_count + 6'd1;
			end else begin
				done <= 1'b1;
				one_more_write <= 1'd0;
			end
			
			address <= write_column_count + write_row_count + write_matrix_offset;
			
			if(address > 18'd38400 && write_element_count > 6'd0) begin
				write_UV <= 1'b1;
			end
			
		end else begin
			fetch_element_count <= 7'd0;
			write_element_count <= 6'd0;
			done <= 1'b0;
			DP_RAM <= 1'b0;
			//column_count <= 3'd0;
			//row_count <= 13'd0;
		end
	end
end
	
endmodule
