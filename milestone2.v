`timescale 1ns/100ps
`default_nettype none

`include "define_state.h"

module milestone2(
/////// board clocks                      ////////////
		input logic CLOCK_50_I,                   // 50 MHz clock
		input logic resetn,								//Reset_n signal
		input logic [15:0] read_data,					//Read data
		input logic startmilestone2,					//to start milestone2
		output logic DP_RAM,
		output logic[17:0] address,
		output logic[15:0] write_data,
		output logic we_n,
		output logic endmilestone2,
		output logic [7:0] RAM_address,
		output logic continue_milestone3,
		output logic address_flag						//This is 1 when M2 takes the SRAM (during writing: A35 -  ... and 0 otherwise.
);


parameter FETCH_OFFSET = 18'd76800,		// Location of the start of the S' values
			 T_OFFSET = 7'd64;  				// Location of the start of the T values in embedded memories

//Misc
M2_state_type state;
logic RAM_select; 						   // 1 for RAM1, 0 for RAM2
logic start_flag;								// 1 if we are on the first matrix. 0 if not.
logic stop_flag;								// 1 if we are on the last matrix.
logic [5:0] write_count;
logic first_cycle;

//Megastate B
logic megastateB_common_case; 			// 1 if in the common case for megastate b, and 0 if not.
logic [3:0] megastateB_counter; 			// Megastate B iterates through the common case 8 times, we count to make sure we haven't reached the end yet.

//Megastate A
//logic megastateA_common_case;
logic [7:0] megastateA_fetch_counter;
logic [3:0] megastateA_counter;

//Some buffer action
logic [31:0] MAC [7:0];
logic [31:0] MAC_buffer [7:0];

//Control signals for the SRAM address_generator
logic SRAM_begin_fetching;
logic SRAM_begin_writing;
logic SRAM_operation_complete;

//SRAM row and column stuff
logic [3:0] SRAM_row_count;
logic [11:0] SRAM_column_count;
logic [17:0] SRAM_matrix_count;
logic [5:0] matrix_incremented;
logic [1:0] matrix_fetch_lead_out;
logic [11:0] SRAM_write_column_count;
logic [3:0] SRAM_write_row_count;
logic [17:0] SRAM_write_matrix_count;
logic [5:0] write_matrix_incremented;

//Multiplier variables
logic [31:0] mult0_result, mult1_result, mult2_result, mult3_result;
logic [31:0] mult_op1;

//RAM variables
logic [6:0] C_address1, C_address2;
logic [6:0] RAM1_address1, RAM1_address2;
logic [6:0] RAM2_address1, RAM2_address2;
logic [31:0] C_read_data1, C_read_data2;
logic [31:0] RAM1_read_data1, RAM1_read_data2;
logic [31:0] RAM2_read_data1, RAM2_read_data2;
logic [31:0] RAM1_write_data1, RAM1_write_data2;
logic [31:0] RAM2_write_data1, RAM2_write_data2;
logic RAM1_wren1, RAM1_wren2;
logic RAM2_wren1, RAM2_wren2;

//Multipliers instantiated here.				
multiplier mult0(.op1(mult_op1), .op2({{16{C_read_data1[31]}}, C_read_data1[31:16]}), .result(mult0_result));
multiplier mult1(.op1(mult_op1), .op2({{16{C_read_data1[15]}}, C_read_data1[15:0]}), .result(mult1_result));
multiplier mult2(.op1(mult_op1), .op2({{16{C_read_data2[31]}}, C_read_data2[31:16]}), .result(mult2_result));
multiplier mult3(.op1(mult_op1), .op2({{16{C_read_data2[15]}}, C_read_data2[15:0]}), .result(mult3_result));

//Multiplier logic
assign mult_op1 = (RAM_select == 1'b1) ? RAM1_read_data1 : RAM2_read_data1;

//Instantiate the address generator
address_generator SRAM_address(
	.clock(CLOCK_50_I),
	.resetn(resetn),
	.fetch_address_enable(SRAM_begin_fetching),
	.write_address_enable(SRAM_begin_writing),
	.address(address),
	.RAM_address(RAM_address),
	.DP_RAM(DP_RAM),
	.done(SRAM_operation_complete),
	.first_cycle(first_cycle)
);

//Instantiate all of the dual-port RAMs
// C RAM
C_values RAMC (
	.address_a ( C_address1 ),
	.address_b ( C_address2 ),
	.clock ( CLOCK_50_I ),
	.data_a ( 32'b0 ),
	.data_b ( 32'b0 ),
	.wren_a ( 1'b0 ),
	.wren_b ( 1'b0 ),
	.q_a ( C_read_data1 ),
	.q_b ( C_read_data2 ) 
	);

// Memory RAM 1
project_mem1 RAM1 (
	.address_a ( RAM1_address1 ),
	.address_b ( RAM1_address2 ),
	.clock ( CLOCK_50_I ),
	.data_a ( RAM1_write_data1 ),
	.data_b ( RAM1_write_data2 ),
	.wren_a ( RAM1_wren1 ),
	.wren_b ( RAM1_wren2 ),
	.q_a ( RAM1_read_data1 ),
	.q_b ( RAM1_read_data2 )
	);

// Memory RAM 2
project_mem2 RAM2 (
	.address_a ( RAM2_address1 ),
	.address_b ( RAM2_address2 ),
	.clock ( CLOCK_50_I ),
	.data_a ( RAM2_write_data1 ),
	.data_b ( RAM2_write_data2 ),
	.wren_a ( RAM2_wren1 ),
	.wren_b ( RAM2_wren2 ),
	.q_a ( RAM2_read_data1 ),
	.q_b ( RAM2_read_data2 )
	);

	
//FSM
always_ff @(posedge CLOCK_50_I or negedge resetn) begin
	if(resetn == 1'b0) begin
		state <= S_M2_IDLE;
		we_n <= 1'b1;
		write_data <= 16'd0;
		megastateB_common_case <= 1'b0;
		megastateB_counter <= 4'b0;
//		megastateA_common_case <= 1'b0;
		megastateA_counter <= 4'b0;
		endmilestone2 <= 1'b0;
		SRAM_begin_fetching <= 1'b0;
		SRAM_begin_writing <= 1'b0;
		write_count <= 6'd0;
		RAM1_address1 <= 7'd0;
		RAM1_address2 <= 7'd0;
		RAM2_address1 <= 7'd0;
		RAM2_address2 <= 7'd0;
		RAM_select <= 1'b1;
		stop_flag <= 1'b0;
		first_cycle <= 1'b0;
		continue_milestone3 <= 1'b0;
		address_flag <= 1'b0;
	end else begin
	
		case (state)
		S_M2_IDLE: begin
			if(startmilestone2 == 1'b1) begin
				we_n <= 1'b1;
				megastateB_common_case <= 1'b0;
				megastateB_counter <= 4'b0;
//				megastateA_common_case <= 1'b0;
				megastateA_counter <= 4'b0;
				SRAM_begin_fetching <= 1'b0;
				SRAM_begin_writing <= 1'b0;
				write_count <= 6'd0;
				RAM1_address1 <= 7'd0;
				RAM1_address2 <= 7'd0;
				RAM2_address1 <= 7'd0;
				RAM2_address2 <= 7'd0;
				RAM_select <= 1'b1;
				stop_flag <= 1'b0;
				first_cycle <= 1'b1;
				continue_milestone3 <= 1'b0;
				address_flag <= 1'b0;
				state <= S_M2_FETCH0;
			end
			endmilestone2 <= 1'b0;
		end
		
		S_M2_FETCH0: begin
			SRAM_begin_fetching <= 1'b1;
			first_cycle <= 1'b0;
			state <= S_M2_FETCH1;
		end
		
		S_M2_FETCH1: begin
			SRAM_begin_fetching <= 1'b0;
			state <= S_M2_FETCH2;
		end
		
		S_M2_FETCH2: begin
			state <= S_M2_FETCH3;
		end
		
		S_M2_FETCH3: begin
			state <= S_M2_FETCH4;
		end
		
		S_M2_FETCH4: begin
			RAM1_address1 <= 7'd0;
			RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
			RAM1_wren1 <= 1'b1;
			
			//Next state stuff
			state <= S_M2_FETCH5;
		end
		
		S_M2_FETCH5: begin
			RAM1_address1 <= RAM1_address1 + 7'd1;
			RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
			
			//Next state stuff
			if(SRAM_operation_complete == 1'b1) begin
				state <= S_M2_FETCH7;
			end else begin
				state <= S_M2_FETCH5;
			end
		end
		
		S_M2_FETCH6: begin
			//Writing to the RAM
			RAM1_address1 <= RAM1_address1 + 7'd1;
			RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
			
			//Next state stuff
			state <= S_M2_FETCH7;
		end
		
		S_M2_FETCH7: begin
			RAM1_address1 <= RAM1_address1 + 7'd1;
			RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
			
			RAM_select <= 1'b1;
			continue_milestone3 <= 1'b1;
			state <= S_M2_B0;
			start_flag <= 1'b1;
		end
		
		// Enter megastate, set to ignore writing.
		// Don't forget to turn off RAM1's wren!
		//LEAD IN: S_M2_B0 - S_M2_B1
		//COMMON CASE: S_M2_B2 - S_M2_B17
		//LEAD OUT: S_M2_B18 - S_M2_B25
		S_M2_B0: begin
			// If start:
			C_address1 <= 7'd0;
			C_address2 <= 7'd1;
				
			if (RAM_select) begin
				RAM1_address1 <= 7'd0;
				RAM1_address2 <= T_OFFSET;
				RAM1_wren1 <= 1'b0;
			end else begin
				RAM2_address1 <= 7'd0;
				RAM2_address2 <= T_OFFSET;
				RAM2_wren1 <= 1'b0;
			end
			
			state <= S_M2_B1;
			continue_milestone3 <= 1'b0;
		end
		
		S_M2_B1: begin
			// If start:
			//C_address1 <= 7'd0;
			//C_address2 <= 7'd1;
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			state <= S_M2_B2;
		end
		
		S_M2_B2: begin
			// If start:
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC storage 
			MAC[0] <= mult0_result;
			MAC[1] <= mult1_result;
			MAC[2] <= mult2_result;
			MAC[3] <= mult3_result;
			
			//Writing stuff
			if(megastateB_common_case == 1'b1) begin
				MAC_buffer[0] <= MAC[0];
				MAC_buffer[1] <= MAC[1];
				MAC_buffer[2] <= MAC[2];
				MAC_buffer[3] <= MAC[3];
				MAC_buffer[4] <= MAC[4];
				MAC_buffer[5] <= MAC[5];
				MAC_buffer[6] <= MAC[6];
				MAC_buffer[7] <= MAC[7];
				
				//Writing stuff
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd1;
					RAM1_write_data2 <= {{8{MAC[1][31]}}, MAC[1][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd1;
					RAM2_write_data2 <= {{8{MAC[1][31]}}, MAC[1][31:8]};
				end
			end
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B3;
		end
		
		S_M2_B3: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= mult0_result;
			MAC[5] <= mult1_result;
			MAC[6] <= mult2_result;
			MAC[7] <= mult3_result;
			
			//Writing stuff
			if(megastateB_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd1;
					RAM1_write_data2 <= {{8{MAC_buffer[2][31]}}, MAC_buffer[2][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd1;
					RAM2_write_data2 <= {{8{MAC_buffer[2][31]}}, MAC_buffer[2][31:8]};
				end
			end
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B4;
		end	
		
		S_M2_B4: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing stuff
			if(megastateB_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd1;
					RAM1_write_data2 <= {{8{MAC_buffer[3][31]}}, MAC_buffer[3][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd1;
					RAM2_write_data2 <= {{8{MAC_buffer[3][31]}}, MAC_buffer[3][31:8]};
				end
			end
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B5;
		end
		
		S_M2_B5: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			if(megastateB_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd1;
					RAM1_write_data2 <= {{8{MAC_buffer[4][31]}}, MAC_buffer[4][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd1;
					RAM2_write_data2 <= {{8{MAC_buffer[4][31]}}, MAC_buffer[4][31:8]};
				end
			end
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B6;
		end
		
		S_M2_B6: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing stuff
			if(megastateB_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd1;
					RAM1_write_data2 <= {{8{MAC_buffer[5][31]}}, MAC_buffer[5][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd1;
					RAM2_write_data2 <= {{8{MAC_buffer[5][31]}}, MAC_buffer[5][31:8]};
				end
			end
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B7;		
		end
		
		S_M2_B7: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			if(megastateB_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd1;
					RAM1_write_data2 <= {{8{MAC_buffer[6][31]}}, MAC_buffer[6][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd1;
					RAM2_write_data2 <= {{8{MAC_buffer[6][31]}}, MAC_buffer[6][31:8]};
				end
			end
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B8;
		end
		
		S_M2_B8: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing stuff
			if(megastateB_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd1;
					RAM1_write_data2 <= {{8{MAC_buffer[7][31]}}, MAC_buffer[7][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd1;
					RAM2_write_data2 <= {{8{MAC_buffer[7][31]}}, MAC_buffer[7][31:8]};
				end
			end
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			//Next state stuff
			state <= S_M2_B9;
		end
		
		S_M2_B9: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			if(megastateB_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd1;
					RAM1_wren2 <= 1'b0;
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd1;
					RAM2_wren2 <= 1'b0;
				end
			end
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B10;
		end	
		
		S_M2_B10: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B11;
		end
		
		S_M2_B11: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B12;
		end
		
		S_M2_B12: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B13;
		end
		
		S_M2_B13: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B14;		
		end
		
		S_M2_B14: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B15;
		end
		
		S_M2_B15: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B16;
			megastateB_counter <= megastateB_counter + 4'd1;
		end
		
		S_M2_B16: begin
			//Addressing stuff
			C_address1 <= 7'd0;
			C_address2 <= 7'd1;
			//C_address1 <= C_address1 + 7'd2;
			//C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			state <= S_M2_B17;
		end
		
		S_M2_B17: begin
			//Addressing stuff
			//C_address1 <= 7'd0;
			//C_address2 <= 7'd1;
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;

			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			if (RAM_select) begin
				RAM1_wren2 <= 1'b1;
				RAM1_write_data2 <= {{8{MAC[0][31]}}, MAC[0][31:8]};
			end else begin
				RAM2_wren2 <= 1'b1;
				RAM2_write_data2 <= {{8{MAC[0][31]}}, MAC[0][31:8]};
			end
			
			//Writing to the SRAM
			if(start_flag == 1'b0) begin
				if(write_count <= 6'd31) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd2;
						RAM2_address2 <= RAM2_address2 + 7'd2;
						write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
												  |RAM2_read_data1[30:24] ? 8'hff : 
												  RAM2_read_data1[23:16];
						write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
												 |RAM2_read_data2[30:24] ? 8'hff : 
												 RAM2_read_data2[23:16];											 
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd2;
						RAM1_address2 <= RAM1_address2 + 7'd2;
						write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
												  |RAM1_read_data1[30:24] ? 8'hff : 
												  RAM1_read_data1[23:16];
						write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
												 |RAM1_read_data2[30:24] ? 8'hff : 
												 RAM1_read_data2[23:16];
					end
					write_count <= write_count + 6'd1;
				end else begin
					we_n <= 1'b1;
					address_flag <= 1'b0;
				end
			end
			
			//Next state stuff
			if (megastateB_counter == 4'd8) begin
				megastateB_common_case <= 1'b0;
				megastateB_counter <= 4'd0;
				state <= S_M2_B18;
				write_count <= 6'd0;
			end else begin
				megastateB_common_case <= 1'b1;
				state <= S_M2_B2;
			end
		end
		
		S_M2_B18: begin
			//Addressing stuff (for T calculations now)
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC storage 
			MAC[0] <= mult0_result;
			MAC[1] <= mult1_result;
			MAC[2] <= mult2_result;
			MAC[3] <= mult3_result;
			
			MAC_buffer[0] <= MAC[0];
			MAC_buffer[1] <= MAC[1];
			MAC_buffer[2] <= MAC[2];
			MAC_buffer[3] <= MAC[3];
			MAC_buffer[4] <= MAC[4];
			MAC_buffer[5] <= MAC[5];
			MAC_buffer[6] <= MAC[6];
			MAC_buffer[7] <= MAC[7];
		
			//Writing stuff
			if (RAM_select) begin
				RAM1_address2 <= RAM1_address2 + 7'd1;
				RAM1_write_data2 <= {{8{MAC[1][31]}}, MAC[1][31:8]};
			end else begin
				RAM2_address2 <= RAM2_address2 + 7'd1;
				RAM2_write_data2 <= {{8{MAC[1][31]}}, MAC[1][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_B19;
		end
		
		S_M2_B19: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= mult0_result;
			MAC[5] <= mult1_result;
			MAC[6] <= mult2_result;
			MAC[7] <= mult3_result;
			
			//Writing stuff
			if (RAM_select) begin
				RAM1_address2 <= RAM1_address2 + 7'd1;
				RAM1_write_data2 <= {{8{MAC_buffer[2][31]}}, MAC_buffer[2][31:8]};
			end else begin
				RAM2_address2 <= RAM2_address2 + 7'd1;
				RAM2_write_data2 <= {{8{MAC_buffer[2][31]}}, MAC_buffer[2][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_B20;
		end
		
		S_M2_B20: begin
			//Addressing stuff 
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC storage 
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing stuff
			if (RAM_select) begin
				RAM1_address2 <= RAM1_address2 + 7'd1;
				RAM1_write_data2 <= {{8{MAC_buffer[3][31]}}, MAC_buffer[3][31:8]};
			end else begin
				RAM2_address2 <= RAM2_address2 + 7'd1;
				RAM2_write_data2 <= {{8{MAC_buffer[3][31]}}, MAC_buffer[3][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_B21;
		end
		
		S_M2_B21: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			if (RAM_select) begin
				RAM1_address2 <= RAM1_address2 + 7'd1;
				RAM1_write_data2 <= {{8{MAC_buffer[4][31]}}, MAC_buffer[4][31:8]};
			end else begin
				RAM2_address2 <= RAM2_address2 + 7'd1;
				RAM2_write_data2 <= {{8{MAC_buffer[4][31]}}, MAC_buffer[4][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_B22;
		end
		
		S_M2_B22: begin
			//Addressing stuff 
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC storage 
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing stuff
			if (RAM_select) begin
				RAM1_address2 <= RAM1_address2 + 7'd1;
				RAM1_write_data2 <= {{8{MAC_buffer[5][31]}}, MAC_buffer[5][31:8]};
			end else begin
				RAM2_address2 <= RAM2_address2 + 7'd1;
				RAM2_write_data2 <= {{8{MAC_buffer[5][31]}}, MAC_buffer[5][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_B23;
		end
		
		S_M2_B23: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			if (RAM_select) begin
				RAM1_address2 <= RAM1_address2 + 7'd1;
				RAM1_write_data2 <= {{8{MAC_buffer[6][31]}}, MAC_buffer[6][31:8]};
			end else begin
				RAM2_address2 <= RAM2_address2 + 7'd1;
				RAM2_write_data2 <= {{8{MAC_buffer[6][31]}}, MAC_buffer[6][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_B24;
		end
		
		S_M2_B24: begin
			//Addressing stuff 
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC storage 
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result; 
			
			//Writing Stuff
			if (RAM_select) begin
				RAM1_address2 <= RAM1_address2 + 7'd1;
				RAM1_write_data2 <= {{8{MAC_buffer[7][31]}}, MAC_buffer[7][31:8]};
			end else begin
				RAM2_address2 <= RAM2_address2 + 7'd1;
				RAM2_write_data2 <= {{8{MAC_buffer[7][31]}}, MAC_buffer[7][31:8]};
			end
			
			//Logic in case we are in the first write, or the last read. 
			start_flag <= 1'b0;
			if(address == 18'd76236) begin
				stop_flag <= 1'b1;
			end
			
			//Next state stuff
			state <= S_M2_A0;		//Go to MEGASTATE A!!			
		end
		
		S_M2_A0: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			if (RAM_select) begin
				RAM1_wren2 <= 1'b0;
			end else begin
				RAM2_wren2 <= 1'b0;
			end
			
			//Next state stuff
			state <= S_M2_A1;
		end
		
		S_M2_A1: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Next state stuff
			state <= S_M2_A2;
		end
		
		S_M2_A2: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			
			//Next state stuff
			state <= S_M2_A3;
		end
		
		S_M2_A3: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Next state stuff
			state <= S_M2_A4;
		end
		
		S_M2_A4: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			
			//READING SRAM WOOOOOO!!!
			if(stop_flag == 1'b0) begin
				SRAM_begin_fetching <= 1'b1;
			end
			
			//Next state stuff
			state <= S_M2_A5;
		end
		
		S_M2_A5: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//READING SRAM WOOOOOO!!!
			if(stop_flag == 1'b0) begin
				SRAM_begin_fetching <= 1'b0;
			end
			
			//Next state stuff
			state <= S_M2_A6;
		end
		
		S_M2_A6: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			
			//READING SRAM WOOOOOO!!!
			//SRAM_fetch_begin <= 1'b0;
			
			//Next state stuff
			state <= S_M2_A7;
		end
		
		S_M2_A7: begin
			//Addressing stuff
			C_address1 <= 7'd0;
			C_address2 <= 7'd1;
			//C_address1 <= C_address1 + 7'd2;
			//C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 - 7'd55;
			end else begin
				RAM2_address1 <= RAM2_address1 - 7'd55;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing stuff
			
			//READING SRAM WOOOOOO!!!
			
			//Next state stuff
			state <= S_M2_A8;
		end
		
		S_M2_A8: begin  // END OF A LEAD-IN
			//Addressing stuff
			//C_address1 <= 7'd0;
			//C_address2 <= 7'd1;
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			if (RAM_select) begin
				RAM1_address2 <= 7'd0;
				RAM1_wren2 <= 1'b1;
				RAM1_write_data2 <= MAC[0];//{{8{MAC[0][31]}}, MAC[0][31:8]};
			end else begin
				RAM2_address2 <= 7'd0;
				RAM2_wren2 <= 1'b1;
				RAM2_write_data2 <= MAC[0];//{{8{MAC[0][31]}}, MAC[0][31:8]};
			end
			
			//READING SRAM WOOOOOO!!!
			if(stop_flag == 1'b0) begin
				if (RAM_select) begin
					RAM2_address1 <= 7'd0;
					RAM2_wren1 <= 1'b1;
					RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
				end else begin
					RAM1_address1 <= 7'd0;
					RAM1_wren1 <= 1'b1;
					RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
				end
			end
			
			matrix_fetch_lead_out <= 2'b00;
			
			//Next state stuff
			state <= S_M2_A9;
		end
		
		S_M2_A9: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC storage 
			MAC[0] <= mult0_result;
			MAC[1] <= mult1_result;
			MAC[2] <= mult2_result;
			MAC[3] <= mult3_result;
			
			//Writing stuff
			//if(megastateA_common_case == 1'b1) begin
				MAC_buffer[0] <= MAC[0];
				MAC_buffer[1] <= MAC[1];
				MAC_buffer[2] <= MAC[2];
				MAC_buffer[3] <= MAC[3];
				MAC_buffer[4] <= MAC[4];
				MAC_buffer[5] <= MAC[5];
				MAC_buffer[6] <= MAC[6];
				MAC_buffer[7] <= MAC[7];
				
				//Writing stuff
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd8;
					RAM1_write_data2 <= MAC[1];//{{8{MAC[1][31]}}, MAC[1][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd8;
					RAM2_write_data2 <= MAC[1];//{{8{MAC[1][31]}}, MAC[1][31:8]};
				end
			//end
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					continue_milestone3 <= 1'b1;
					matrix_fetch_lead_out <= 2'b10;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			
			//Next state stuff
			state <= S_M2_A10;
		end
		
		S_M2_A10: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= mult0_result;
			MAC[5] <= mult1_result;
			MAC[6] <= mult2_result;
			MAC[7] <= mult3_result;
			
			//Writing stuff
			//if(megastateA_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd8;
					RAM1_write_data2 <= MAC_buffer[2];//{{8{MAC_buffer[2][31]}}, MAC_buffer[2][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd8;
					RAM2_write_data2 <= MAC_buffer[2];//{{8{MAC_buffer[2][31]}}, MAC_buffer[2][31:8]};
				end
			//end
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b10;
					continue_milestone3 <= 1'b1;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;					
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			
			//Next state stuff
			state <= S_M2_A11;
		end		
		
		S_M2_A11: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing stuff
			//if(megastateA_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd8;
					RAM1_write_data2 <= MAC_buffer[3];//{{8{MAC_buffer[3][31]}}, MAC_buffer[3][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd8;
					RAM2_write_data2 <= MAC_buffer[3];//{{8{MAC_buffer[3][31]}}, MAC_buffer[3][31:8]};
				end
			//end
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b10;
					continue_milestone3 <= 1'b1;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			//Next state stuff
			state <= S_M2_A12;
		end		
		
		S_M2_A12: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			//if(megastateA_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd8;
					RAM1_write_data2 <= MAC_buffer[4];//{{8{MAC_buffer[4][31]}}, MAC_buffer[4][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd8;
					RAM2_write_data2 <= MAC_buffer[4];//{{8{MAC_buffer[4][31]}}, MAC_buffer[4][31:8]};
				end
			//end
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b10;
					continue_milestone3 <= 1'b1;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			
			//Next state stuff
			state <= S_M2_A13;
		end
		
		S_M2_A13: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing stuff
			//if(megastateA_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd8;
					RAM1_write_data2 <= MAC_buffer[5];//{{8{MAC_buffer[5][31]}}, MAC_buffer[5][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd8;
					RAM2_write_data2 <= MAC_buffer[5]; //{{8{MAC_buffer[5][31]}}, MAC_buffer[5][31:8]};
				end
			//end
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					continue_milestone3 <= 1'b1;
					matrix_fetch_lead_out <= 2'b10;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			//Next state stuff
			state <= S_M2_A14;		
		end
		
		S_M2_A14: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			//if(megastateA_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd8;
					RAM1_write_data2 <= MAC_buffer[6];//{{8{MAC_buffer[6][31]}}, MAC_buffer[6][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd8;
					RAM2_write_data2 <= MAC_buffer[6];//{{8{MAC_buffer[6][31]}}, MAC_buffer[6][31:8]};
				end
			//end
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					continue_milestone3 <= 1'b1;
					matrix_fetch_lead_out <= 2'b10;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			
			//Next state stuff
			state <= S_M2_A15;
		end
		
		S_M2_A15: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Writing stuff
			//if(megastateA_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 + 7'd8;
					RAM1_write_data2 <= MAC_buffer[7]; //{{8{MAC_buffer[7][31]}}, MAC_buffer[7][31:8]};
				end else begin
					RAM2_address2 <= RAM2_address2 + 7'd8;
					RAM2_write_data2 <= MAC_buffer[7]; //{{8{MAC_buffer[7][31]}}, MAC_buffer[7][31:8]};
				end
			//end
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					continue_milestone3 <= 1'b1;
					matrix_fetch_lead_out <= 2'b10;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			
			//Next state stuff
			state <= S_M2_A16;
		end
		
		S_M2_A16: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			//if(megastateA_common_case == 1'b1) begin
				if (RAM_select) begin
					RAM1_address2 <= RAM1_address2 - 7'd55;
					RAM1_wren2 <= 1'b0;
				end else begin
					RAM2_address2 <= RAM2_address2 - 7'd55;
					RAM2_wren2 <= 1'b0;
				end
			//end
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					continue_milestone3 <= 1'b1;
					matrix_fetch_lead_out <= 2'b10;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					continue_milestone3 <= 1'b0;
					matrix_fetch_lead_out <= 2'b11;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			
			//Next state stuff
			state <= S_M2_A17;
		end
		
		S_M2_A17: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					continue_milestone3 <= 1'b1;
					matrix_fetch_lead_out <= 2'b10;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			
			//Next state stuff
			state <= S_M2_A18;
		end
		
		S_M2_A18: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					continue_milestone3 <= 1'b1;
					matrix_fetch_lead_out <= 2'b10;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			
			//Next state stuff
			state <= S_M2_A19;
		end
		
		S_M2_A19: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					continue_milestone3 <= 1'b1;
					matrix_fetch_lead_out <= 2'b10;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			//Next state stuff
			state <= S_M2_A20;
		end
		
		S_M2_A20: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] +mult3_result;
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b10;
					continue_milestone3 <= 1'b1;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			
			//Next state stuff
			state <= S_M2_A21;		
		end
		
		S_M2_A21: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd8;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd8;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					continue_milestone3 <= 1'b1;
					matrix_fetch_lead_out <= 2'b10;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			
			//Next state stuff
			state <= S_M2_A22;
		end
		
		S_M2_A22: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					continue_milestone3 <= 1'b1;
					matrix_fetch_lead_out <= 2'b10;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					matrix_fetch_lead_out <= 2'b11;
					continue_milestone3 <= 1'b0;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			
			//Next state stuff
			state <= S_M2_A23;
			megastateA_counter <= megastateA_counter + 4'd1;
		end
		
		S_M2_A23: begin
			//Addressing stuff
			C_address1 <= 7'd0;
			C_address2 <= 7'd1;
			//C_address1 <= C_address1 + 7'd2;
			//C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 - 7'd55;
			end else begin
				RAM2_address1 <= RAM2_address1 - 7'd55;
			end
			
			if(stop_flag == 1'b0) begin
				if(megastateA_counter == 4'd7) begin
					if (RAM_select) begin
						RAM2_address1 <= 7'd0; 
					end else begin
						RAM1_address1 <= 7'd0;
					end
				end
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					continue_milestone3 <= 1'b1;
					matrix_fetch_lead_out <= 2'b10;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					continue_milestone3 <= 1'b0;
					matrix_fetch_lead_out <= 2'b11;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
			
			//Next state stuff
			state <= S_M2_A24;
		end
		
		S_M2_A24: begin
			//Addressing stuff
			//C_address1 <= 7'd0;
			//C_address2 <= 7'd1;
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Writing stuff
			if (RAM_select) begin
				RAM1_wren2 <= 1'b1;
				RAM1_write_data2 <= MAC[0];//{{8{MAC[0][31]}}, MAC[0][31:8]};
			end else begin
				RAM2_wren2 <= 1'b1;
				RAM2_write_data2 <= MAC[0];//{{8{MAC[0][31]}}, MAC[0][31:8]};
			end
			
			//READING SRAM WOOOOOO!!!
			// If fetch == 3, do nothing.
			if(stop_flag == 1'b0) begin
				if (SRAM_operation_complete == 1'b1) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					matrix_fetch_lead_out <= 2'b01;
				end else if (matrix_fetch_lead_out == 2'b01) begin
					if(RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;	
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
					continue_milestone3 <= 1'b1;
					matrix_fetch_lead_out <= 2'b10;
				end else if (matrix_fetch_lead_out == 2'b10) begin
					if (RAM_select) begin
						RAM2_wren1 <= 1'b0;
					end else begin
						RAM1_wren1 <= 1'b0;
					end
					continue_milestone3 <= 1'b0;
					matrix_fetch_lead_out <= 2'b11;
				end else if (matrix_fetch_lead_out == 2'b00) begin
					if (RAM_select) begin
						RAM2_address1 <= RAM2_address1 + 7'd1;	
						RAM2_write_data1 <= {{16{read_data[15]}}, read_data};
					end else begin
						RAM1_address1 <= RAM1_address1 + 7'd1;
						RAM1_write_data1 <= {{16{read_data[15]}}, read_data};
					end
				end
			end
				
			//Next state stuff
			if (megastateA_counter == 4'd7) begin
//				megastateA_common_case <= 1'b0;
				megastateA_counter <= 4'd0;
				matrix_fetch_lead_out <= 2'b00;
				
				//Time to switch RAMs
				if (RAM_select == 1'b1) begin
					RAM_select <= 1'b0;
				end else begin
					RAM_select <= 1'b1;
				end
				
				state <= S_M2_A25;
			end else begin
//				megastateA_common_case <= 1'b1;
				state <= S_M2_A9;
			end
		end
		
		S_M2_A25: begin				//LEAD OUT STARTS HERE
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC storage 
			if(stop_flag == 1'b0) begin
				MAC[0] <= mult0_result;
				MAC[1] <= mult1_result;
				MAC[2] <= mult2_result;
				MAC[3] <= mult3_result;
			end
			
			//Writing stuff
			MAC_buffer[0] <= MAC[0];
			MAC_buffer[1] <= MAC[1];
			MAC_buffer[2] <= MAC[2];
			MAC_buffer[3] <= MAC[3];
			MAC_buffer[4] <= MAC[4];
			MAC_buffer[5] <= MAC[5];
			MAC_buffer[6] <= MAC[6];
			MAC_buffer[7] <= MAC[7];
			
			//Writing stuff
			if (RAM_select) begin
				RAM2_address2 <= RAM2_address2 + 7'd8;
				RAM2_write_data2 <= MAC[1];//{{8{MAC[1][31]}}, MAC[1][31:8]};
			end else begin
				RAM1_address2 <= RAM1_address2 + 7'd8;
				RAM1_write_data2 <= MAC[1];//{{8{MAC[1][31]}}, MAC[1][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_A26;
		end
		
		S_M2_A26: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			if(stop_flag == 1'b0) begin
				MAC[4] <= mult0_result;
				MAC[5] <= mult1_result;
				MAC[6] <= mult2_result;
				MAC[7] <= mult3_result;
			end
			
			//Writing stuff
			if (RAM_select) begin
				RAM2_address2 <= RAM2_address2 + 7'd8;
				RAM2_write_data2 <= MAC_buffer[2];//{{8{MAC_buffer[2][31]}}, MAC_buffer[2][31:8]};
			end else begin
				RAM1_address2 <= RAM1_address2 + 7'd8;
				RAM1_write_data2 <= MAC_buffer[2];//{{8{MAC_buffer[2][31]}}, MAC_buffer[2][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_A27;//B4
		end
		
		
		S_M2_A27: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC Storage
			if(stop_flag == 1'b0) begin
				MAC[0] <= MAC[0] + mult0_result;
				MAC[1] <= MAC[1] + mult1_result;
				MAC[2] <= MAC[2] + mult2_result;
				MAC[3] <= MAC[3] + mult3_result;
			end
			
			//Writing stuff
			if (RAM_select) begin
				RAM2_address2 <= RAM2_address2 + 7'd8;
				RAM2_write_data2 <= MAC_buffer[3]; //{{8{MAC_buffer[3][31]}}, MAC_buffer[3][31:8]};
			end else begin
				RAM1_address2 <= RAM1_address2 + 7'd8;
				RAM1_write_data2 <= MAC_buffer[3]; //{{8{MAC_buffer[3][31]}}, MAC_buffer[3][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_A28;//B5
		end
		
		S_M2_A28: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			if(stop_flag == 1'b0) begin
				MAC[4] <= MAC[4] + mult0_result;
				MAC[5] <= MAC[5] + mult1_result;
				MAC[6] <= MAC[6] + mult2_result;
				MAC[7] <= MAC[7] + mult3_result;
			end
			
			//Writing stuff
			if (RAM_select) begin
				RAM2_address2 <= RAM2_address2 + 7'd8;
				RAM2_write_data2 <= MAC_buffer[4];//{{8{MAC_buffer[4][31]}}, MAC_buffer[4][31:8]};
			end else begin
				RAM1_address2 <= RAM1_address2 + 7'd8;
				RAM1_write_data2 <= MAC_buffer[4];//{{8{MAC_buffer[4][31]}}, MAC_buffer[4][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_A29;  //B6
		end
		
		S_M2_A29: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC Storage
			if(stop_flag == 1'b0) begin
				MAC[0] <= MAC[0] + mult0_result;
				MAC[1] <= MAC[1] + mult1_result;
				MAC[2] <= MAC[2] + mult2_result;
				MAC[3] <= MAC[3] + mult3_result;
			end
			
			//Writing stuff
			if (RAM_select) begin
				RAM2_address2 <= RAM2_address2 + 7'd8;
				RAM2_write_data2 <= MAC_buffer[5];//{{8{MAC_buffer[5][31]}}, MAC_buffer[5][31:8]};
			end else begin
				RAM1_address2 <= RAM1_address2 + 7'd8;
				RAM1_write_data2 <= MAC_buffer[5];//{{8{MAC_buffer[5][31]}}, MAC_buffer[5][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_A30;	//B7
		end
		
		S_M2_A30: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			if(stop_flag == 1'b0) begin
				MAC[4] <= MAC[4] + mult0_result;
				MAC[5] <= MAC[5] + mult1_result;
				MAC[6] <= MAC[6] + mult2_result;
				MAC[7] <= MAC[7] + mult3_result;
			end
			
			//Writing stuff
			if (RAM_select) begin
				RAM2_address2 <= RAM2_address2 + 7'd8;
				RAM2_write_data2 <= MAC_buffer[6];//{{8{MAC_buffer[6][31]}}, MAC_buffer[6][31:8]};
			end else begin
				RAM1_address2 <= RAM1_address2 + 7'd8;
				RAM1_write_data2 <= MAC_buffer[6];//{{8{MAC_buffer[6][31]}}, MAC_buffer[6][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_A31; //B8
		end
		
		S_M2_A31: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC Storage
			if(stop_flag == 1'b0) begin
				MAC[0] <= MAC[0] + mult0_result;
				MAC[1] <= MAC[1] + mult1_result;
				MAC[2] <= MAC[2] + mult2_result;
				MAC[3] <= MAC[3] + mult3_result;
			end
			
			//Writing stuff
			if (RAM_select) begin
				RAM2_address2 <= RAM2_address2 + 7'd8;
				RAM2_write_data2 <= MAC_buffer[7];//{{8{MAC_buffer[7][31]}}, MAC_buffer[7][31:8]};
			end else begin
				RAM1_address2 <= RAM1_address2 + 7'd8;
				RAM1_write_data2 <= MAC_buffer[7];//{{8{MAC_buffer[7][31]}}, MAC_buffer[7][31:8]};
			end
			
			//Next state stuff
			state <= S_M2_A32;		//B9
		end
		
		S_M2_A32: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			if(stop_flag == 1'b0) begin
				MAC[4] <= MAC[4] + mult0_result;
				MAC[5] <= MAC[5] + mult1_result;
				MAC[6] <= MAC[6] + mult2_result;
				MAC[7] <= MAC[7] + mult3_result;
			end
			
			//Writing stuff
			if (RAM_select) begin
				RAM2_address2 <= RAM2_address2 + 7'd1;
				RAM2_wren2 <= 1'b0;
			end else begin
				RAM1_address2 <= RAM1_address2 + 7'd1;
				RAM1_wren2 <= 1'b0;
			end
				
			//Next state stuff			
			if(stop_flag == 1'b1) begin
				state <= S_M2_WRITE0;
				address_flag <= 1'b1;
			end else begin
				state <= S_M2_A33;
			end
		end
		
		S_M2_A33: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
		
			//Overlap with Megastate B
			if (RAM_select) begin
				RAM2_address1 <= 7'd0;
				RAM2_address2 <= 7'd1;
			end else begin
				RAM1_address1 <= 7'd0;
				RAM1_address2 <= 7'd1;
			end
			
			//Next state stuff
			state <= S_M2_A34;
		end
		
		S_M2_A34: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			
			//MAC Storage
			MAC[4] <= MAC[4] + mult0_result;
			MAC[5] <= MAC[5] + mult1_result;
			MAC[6] <= MAC[6] + mult2_result;
			MAC[7] <= MAC[7] + mult3_result;
			
			//Overlap with megastate B
			SRAM_begin_writing <= 1'b1;
			if (RAM_select) begin
				RAM2_address1 <= RAM2_address1 + 7'd2;
				RAM2_address2 <= RAM2_address2 + 7'd2;
			end else begin
				RAM1_address1 <= RAM1_address1 + 7'd2;
				RAM1_address2 <= RAM1_address2 + 7'd2;
			end
			
			//Next state stuff
			state <= S_M2_A35;
		end
		
		S_M2_A35: begin
			//Addressing stuff
			C_address1 <= C_address1 + 7'd2;
			C_address2 <= C_address2 + 7'd2;
			if (RAM_select) begin
				RAM1_address1 <= RAM1_address1 + 7'd1;
				RAM1_address2 <= T_OFFSET;
			end else begin
				RAM2_address1 <= RAM2_address1 + 7'd1;
				RAM2_address2 <= T_OFFSET;
			end
			
			//MAC Storage
			MAC[0] <= MAC[0] + mult0_result;
			MAC[1] <= MAC[1] + mult1_result;
			MAC[2] <= MAC[2] + mult2_result;
			MAC[3] <= MAC[3] + mult3_result;
			
			//Overlap with Megastate B 
			if (RAM_select) begin
				RAM2_address1 <= RAM2_address1 + 7'd2;
				RAM2_address2 <= RAM2_address2 + 7'd2;
				
				write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
										  |RAM2_read_data1[30:24] ? 8'hff : 
										  RAM2_read_data1[23:16];
				write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
										 |RAM2_read_data2[30:24] ? 8'hff : 
										 RAM2_read_data2[23:16];
			end else begin
				RAM1_address1 <= RAM1_address1 + 7'd2;
				RAM1_address2 <= RAM1_address2 + 7'd2;
				
				write_data[15:8] <= RAM1_read_data1[31] ? 8'd0 :
										  |RAM1_read_data1[30:24] ? 8'hff : 
										  RAM1_read_data1[23:16];
				write_data[7:0] <= RAM1_read_data2[31] ? 8'd0 :
										 |RAM1_read_data2[30:24] ? 8'hff : 
										 RAM1_read_data2[23:16];
			end
			SRAM_begin_writing <= 1'b0;
			we_n <= 1'b0;
			write_count <= write_count + 6'd1;
			address_flag <= 1'b1;
			//Next state stuff
			state <= S_M2_B13;
		end
		
		S_M2_WRITE0: begin
			//Addressing stuff
			RAM2_address1 <= 7'd0;
			RAM2_address2 <= 7'd1;
			
			//MAC Storage 
			
			//Writing stuff
			
			//Next state stuff
			state <= S_M2_WRITE1;
		end
		
		S_M2_WRITE1: begin
			//Addressing stuff
			SRAM_begin_writing <= 1'b1;
			RAM2_address1 <= RAM2_address1 + 7'd2;
			RAM2_address2 <= RAM2_address2 + 7'd2;
			
			//MAC Storage
			
			//Writing stuff
			
			//Next state stuff
			state <= S_M2_WRITE2;
		end
		
		S_M2_WRITE2: begin
			//Addressing stuff
			RAM2_address1 <= RAM2_address1 + 7'd2;
			RAM2_address2 <= RAM2_address2 + 7'd2;
			
			SRAM_begin_writing <= 1'b0;
			we_n <= 1'b0;
			
			//MAC Storage
			
			//Writing stuff
			write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
									  |RAM2_read_data1[30:24] ? 8'hff : 
									  RAM2_read_data1[23:16];
			write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
									 |RAM2_read_data2[30:24] ? 8'hff : 
									 RAM2_read_data2[23:16];
									 
			write_count <= write_count + 6'd1;
			
			//Next state stuff
			state <= S_M2_WRITE3;
		end
		
		S_M2_WRITE3: begin
			//Addressing stuff
			RAM2_address1 <= RAM2_address1 + 7'd2;
			RAM2_address2 <= RAM2_address2 + 7'd2;
		
			//Writing stuff
			write_data[15:8] <= RAM2_read_data1[31] ? 8'd0 :
									  |RAM2_read_data1[30:24] ? 8'hff : 
									  RAM2_read_data1[23:16];
			write_data[7:0] <= RAM2_read_data2[31] ? 8'd0 :
									 |RAM2_read_data2[30:24] ? 8'hff : 
									 RAM2_read_data2[23:16];
									 
			write_count <= write_count + 6'd1;
			
			//Next state stuff
			if (write_count == 6'd31) begin
				state <= S_M2_WRITE4;
			end else begin
				state <= S_M2_WRITE3;
			end
		end
		
		S_M2_WRITE4: begin
			we_n <= 1'b1;
			address_flag <= 1'b0;
			write_count <= 6'd0;
			endmilestone2 <= 1'b1;
			state <= S_M2_IDLE;
		end
		
		default: state <= S_M2_IDLE;
		endcase
	end
	end
endmodule