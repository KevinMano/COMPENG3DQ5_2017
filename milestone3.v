`timescale 1ns/100ps
`default_nettype none

`include "define_state.h"

module milestone3(
/////// board clocks                      ////////////
		input logic CLOCK_50_I,                   // 50 MHz clock
		input logic resetn,								//Reset_n signal
		input logic [15:0] read_data,					//Read data
		input logic start_reading,						//Input from milestone 2 after it finishes fetching
		input logic startmilestone3,
		input logic pause,
		output logic[17:0] address,
		output logic[15:0] DP_write_data,
		output logic DP_we_n,
		output logic error,
		output logic [7:0] DP_RAM_address,
		output logic endM3
);


//Parameter for the SRAM offset where the compressed image bitstream is contained.
parameter FETCH_OFFSET = 18'd76800;//18'd0;

//Misc
M3_state_type state;
M3_state_type previous_state;

//Information from the first few bytes of the bitstream
logic quantization;
logic [14:0] width;
logic [15:0] height;

logic enable;
logic [8:0] var_number;
logic [3:0] repeat_send;
logic first_matrix;

logic [47:0] read_buffer;
logic [5:0] buffer_index;
logic [6:0] element_count;
//logic start_reading;

logic read_shift;					//1 if you should read from SRAM
logic fill;
logic [1:0] timer1, timer2;
logic [1:0] one_read;
assign one_read = timer1+timer2+fill+read_shift;	//Takes the values 0, 1 or 2.
logic [1:0] waiting_fetches;

//Initialize the variable shifter here
//The signals that are currently here are dependent on the module. Finalize before testing.
variable_shifter2 variable_shift (
	.clock(CLOCK_50_I),
	.resetn(resetn),
	.enable(enable),
	.quantization_matrix(quantization),
	.input_bits(var_number),
	.result(DP_write_data),									//Output is 16 bits, we do the shifting.	
	.wren_a(DP_we_n),
	.address_a(DP_RAM_address)
);

//Initialize the last DP RAM here.
//

//Keep track of when information becomes available on read_data
always_ff @(posedge CLOCK_50_I or negedge resetn) begin
	if (resetn == 1'b0) begin
		read_shift <= 1'b0;
		timer1 <= 2'b0;
		timer2 <= 2'b0;
	end else begin
	
		read_shift <= 1'b0;
	
		if (fill == 1'b1) begin
			if (timer1 == 2'b0) timer1 <= 2'b01;
			else timer2 <= 2'b01;
		end
		
		if (timer1 == 2'b01) begin
			read_shift <= 1'b1;
			timer1 <= 2'b0;
		end
		
		if (timer2 == 2'b01) begin
			read_shift <= 1'b1;
			timer2 <= 2'b0;
		end
		
		if(pause == 1'b1 || startmilestone3 == 1'b1) begin
			read_shift <= 1'b0;
			timer1 <= 2'b0;
			timer2 <= 2'b0;
		end 
	end
end

always_ff @(posedge CLOCK_50_I or negedge resetn) begin
	if(resetn == 1'b0) begin
		address <= FETCH_OFFSET;
		enable <= 1'b0;
		error <= 1'b0;
		buffer_index <= 6'd47;
		repeat_send <= 1'b0;
		var_number <= 9'b0;
		fill <= 1'b0;
		element_count <= 7'b0;
		read_buffer <= 48'd0;
		state <= S_M3_IDLE;
		first_matrix <= 1'b1;
		endM3 <= 1'b0;
		waiting_fetches <= 2'b0;
	end else begin
	
		case (state)
		S_M3_IDLE: begin
			if(startmilestone3 == 1'b1) begin
				address <= FETCH_OFFSET;
				enable <= 1'b0;
				error <= 1'b0;
				buffer_index <= 6'd47;
				repeat_send <= 1'b0;
				var_number <= 9'b0;
				fill <= 1'b0;
				read_buffer <= 48'd0;
				element_count <= 7'b0;
				first_matrix <= 1'b1;
				state <= S_M3_IDENT_BEGIN;
				endM3 <= 1'b0;
				waiting_fetches <= 2'b0;
			end
		end
		
		S_M3_IDENT_BEGIN: begin
			address <= FETCH_OFFSET;
			state <= S_M3_IDENT0;
		end
		
		S_M3_IDENT0: begin
			address <= address + 18'd1;
			state <= S_M3_IDENT1;
		end
		
		S_M3_IDENT1: begin
			address <= address + 18'd1;
			state <= S_M3_IDENT2;
		end
		
		S_M3_IDENT2: begin
			address <= address + 18'd1;
			
			//Receive DEAD
			if (read_data != 16'hDEAD) begin
				state <= S_M3_IDLE;
				error <= 1'b1;
			end else begin
				state <= S_M3_IDENT3;
			end
		end
		
		S_M3_IDENT3: begin
			address <= address + 18'd1;
		
			//Receive BEEF
			if (read_data != 16'hBEEF) begin
				state <= S_M3_IDLE;
				error <= 1'b1;
			end else begin
				state <= S_M3_IDENT4;
			end
		end
		
		S_M3_IDENT4: begin
			address <= address + 18'd1;
			
			//Receive Q, width
			quantization <= read_data[15];
			width <= read_data[14:0];
			state <= S_M3_IDENT5;
		end
		
		S_M3_IDENT5: begin
			address <= address + 18'd1;
			
			//Receive height
			height <= read_data;
			state <= S_M3_FILL0;
		end
		
		S_M3_FILL0: begin
			read_buffer[47:32] <= read_data;
			state <= S_M3_FILL1;
		end
		
		S_M3_FILL1: begin
			read_buffer[31:16] <= read_data;
			state <= S_M3_FILL2;
		end
		
		S_M3_FILL2: begin
			read_buffer[15:0] <= read_data;
			state <= S_M3_REPEAT;
		end
		
		S_M3_REPEAT: begin
			if(pause == 1'b1) begin
				waiting_fetches <= one_read;
				previous_state <= state;
				state <= S_M3_PAUSE;
				enable <= 1'b0;
			end else begin
				enable <= 1'b1;
				fill <= 1'b0;
				
				//Perform any fetches
				if (read_shift == 1'b1) begin
					read_buffer[47:16] <= read_buffer[31:0];
					read_buffer[15:0] <= read_data;
					buffer_index <= buffer_index + 6'd16;
				end
				
				//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
				//Determine if any fetches are required
				//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
				if ((buffer_index < 6'd32)&&(timer1 == 2'b0)&&(timer2 == 2'b0)&&(read_shift == 1'b0)&&(fill == 1'b0)) begin
					fill <= 1'b1;
					address <= address + 18'd1;
				end else if ((buffer_index < 6'd16)&&(one_read == 4'd1)) begin
					fill <= 1'b1;
					address <= address + 18'd1;
				end
				
				if (element_count == 7'd64) begin
					enable <= 1'b0;
					element_count <= 7'd0;
					state <= S_M3_MIDIDLE;
				
				end else begin
				
					if (buffer_index < 6'd11) begin
						//Don't do anything until after you fetch more values
						enable <= 1'b0;
					end else begin
				
						if (read_buffer[buffer_index-:2] == 2'b00) begin //9 bit value follows
							var_number <= read_buffer[(buffer_index-4'd2)-:9];
							buffer_index <= (read_shift == 1'b1) ? buffer_index + 4'd5 : buffer_index - 4'd11;
							element_count <= element_count + 1'b1;
							state <= S_M3_REPEAT;
							
						end else if (read_buffer[buffer_index-:2] == 2'b01) begin //4 bit value follows
							var_number <= {{5{read_buffer[(buffer_index-4'd2)]}}, read_buffer[(buffer_index-4'd2)-:4]};
							buffer_index <= (read_shift == 1'b1) ? buffer_index + 4'd10 : buffer_index - 4'd6;
							element_count <= element_count + 1'b1;
							state <= S_M3_REPEAT;
							
						end else if (read_buffer[buffer_index-:3] == 3'b100) begin //Negative ones
							repeat_send <= (read_buffer[(buffer_index-4'd3)-:2] == 2'b00) ? 4'd4 : {2'b0, read_buffer[(buffer_index-4'd3)-:2]};
							var_number <= 9'd511;
							buffer_index <= (read_shift == 1'b1) ? buffer_index + 4'd11 : buffer_index - 4'd5;
							element_count <= element_count + 7'd1;
							
							if (read_buffer[(buffer_index-4'd3)-:2] == 2'b01) begin
								repeat_send <= 4'd0;
								state <= S_M3_REPEAT;
							end else begin
								state <= S_M3_NONES;
							end
							
						end else if (read_buffer[buffer_index-:3] == 3'b101) begin //Ones
							repeat_send <= (read_buffer[(buffer_index-4'd3)-:2] == 2'b00) ? 4'd4 : {2'b0, read_buffer[(buffer_index-4'd3)-:2]};
							var_number <= 9'd1;
							buffer_index <= (read_shift == 1'b1) ? buffer_index + 4'd11 : buffer_index - 4'd5;
							element_count <= element_count + 7'd1;
							
							if (read_buffer[(buffer_index-4'd3)-:2] == 2'b01) begin
								repeat_send <= 4'd0;
								state <= S_M3_REPEAT;
							end else begin
								state <= S_M3_ONES;
							end
							
						end else if (read_buffer[buffer_index-:3] == 3'b110) begin //Zeros
							repeat_send <= (read_buffer[(buffer_index-4'd3)-:3] == 3'b00) ? 4'd8 : {1'b0, read_buffer[(buffer_index-4'd3)-:3]};
							var_number <= 9'd0; 
							buffer_index <= (read_shift == 1'b1) ? buffer_index + 4'd10 : buffer_index - 4'd6;
							element_count <= element_count + 7'd1;
							
							if (read_buffer[(buffer_index-4'd3)-:3] == 3'b01) begin
								repeat_send <= 4'd0;
								state <= S_M3_REPEAT;
							end else begin
								state <= S_M3_ZEROS;
							end
							
						end else begin
							var_number <= 9'd0;
							buffer_index <= (read_shift == 1'b1) ? buffer_index + 4'd13 : buffer_index - 4'd3;
							element_count <= element_count + 7'd1;
							state <= S_M3_ALL_ZEROS;
						end
					end
				end
			end
		end
		
		S_M3_ALL_ZEROS: begin
		// Send var_number = 9'd0 until element_count == 64
			if(pause == 1'b1) begin
				waiting_fetches <= one_read;
				previous_state <= state;
				state <= S_M3_PAUSE;
				enable <= 1'b0;
			end else begin
				enable <= 1'b1;
				fill <= 1'b0;
				if (read_shift == 1'b1) begin
					read_buffer[47:16] <= read_buffer[31:0];
					read_buffer[15:0] <= read_data;
					buffer_index <= buffer_index + 5'd16;
				end
				
				if (element_count == 7'd64) begin
					enable <= 1'b0;
					element_count <= 7'd0;
					state <= S_M3_MIDIDLE;
				end else begin
					var_number <= 9'd0;
					element_count <= element_count + 7'd1;
				end
			end	
		end
		
		S_M3_ZEROS: begin
		// Send var_number = 9'd0 as many times as it says
			if(pause == 1'b1) begin
				waiting_fetches <= one_read;
				previous_state <= state;
				state <= S_M3_PAUSE;
				enable <= 1'b0;
			end else begin
				enable <= 1'b1;
				fill <= 1'b0;
				if (read_shift == 1'b1) begin
					read_buffer[47:16] <= read_buffer[31:0];
					read_buffer[15:0] <= read_data;
					buffer_index <= buffer_index + 6'd16;
				end
				
				if (element_count == 7'd64) begin
					enable <= 1'b0;
					element_count <= 7'd0;
					state <= S_M3_MIDIDLE;
				end else begin
					var_number <= 9'd0;
					element_count <= element_count + 7'd1;
					repeat_send <= repeat_send - 4'd1;
					if (repeat_send == 4'd2) begin
						repeat_send <= 4'd0;
						state <= S_M3_REPEAT;
					end
				end
			end
		end
		
		S_M3_NONES: begin
		// Send negative ones
			if(pause == 1'b1) begin
				waiting_fetches <= one_read;
				previous_state <= state;
				state <= S_M3_PAUSE;
				enable <= 1'b0;
			end else begin
				enable <= 1'b1;
				fill <= 1'b0;
				if (read_shift == 1'b1) begin
					read_buffer[47:16] <= read_buffer[31:0];
					read_buffer[15:0] <= read_data;
					buffer_index <= buffer_index + 6'd16;
				end
				
				if (element_count == 7'd64) begin
					enable <= 1'b0;
					element_count <= 7'd0;
					state <= S_M3_MIDIDLE;
				end else begin
					var_number <= 9'd511;
					element_count <= element_count + 7'd1;
					repeat_send <= repeat_send - 4'd1;
					if (repeat_send == 4'd2) begin
						repeat_send <= 4'd0;
						state <= S_M3_REPEAT;
					end
				end
			end
		end
		
		S_M3_ONES: begin
		// Send ones
			if(pause == 1'b1) begin
				waiting_fetches <= one_read;
				previous_state <= state;
				state <= S_M3_PAUSE;
				enable <= 1'b0;
			end else begin
				enable <= 1'b1;
				fill <= 1'b0;
				if (read_shift == 1'b1) begin
					read_buffer[47:16] <= read_buffer[31:0];
					read_buffer[15:0] <= read_data;
					buffer_index <= buffer_index + 6'd16;
				end
				
				if (element_count == 7'd64) begin
					enable <= 1'b0;
					element_count <= 7'd0;
					state <= S_M3_MIDIDLE;
				end else begin
					var_number <= 9'd1;
					element_count <= element_count + 7'd1;
					repeat_send <= repeat_send - 4'd1;
					if (repeat_send == 4'd2) begin
						repeat_send <= 4'd0;
						state <= S_M3_REPEAT;
					end
				end
			end
		end
		
		S_M3_MIDIDLE: begin
			//Perform any fetches
			fill <= 1'b0;
			if (read_shift == 1'b1) begin
				read_buffer[47:16] <= read_buffer[31:0];
				read_buffer[15:0] <= read_data;
				buffer_index <= buffer_index + 6'd16;
			end
		
			if(startmilestone3 == 1'b1) begin
				// Do all the stuff it would do if it were being reset
				address <= FETCH_OFFSET;
				enable <= 1'b0;
				error <= 1'b0;
				buffer_index <= 6'd47;
				repeat_send <= 1'b0;
				var_number <= 9'b0;
				fill <= 1'b0;
				read_buffer <= 48'd0;
				element_count <= 7'b0;
				first_matrix <= 1'b1;
				state <= S_M3_IDENT_BEGIN;
				waiting_fetches <= 2'b0;
				endM3 <= 1'b0;
			end else if (start_reading == 1'b1) begin
				state <= S_M3_REPEAT;
			end
		
			if(first_matrix == 1'b1) begin
				endM3 <= 1'b1;
				first_matrix <= 1'b0;
			end else begin
				endM3 <= 1'b0;
			end
		end
		
		S_M3_PAUSE: begin
			if(pause == 1'b0) begin
				case(waiting_fetches)
					2'b00: begin
						state <= previous_state;
					end
					
					2'b01: begin
						state <= S_M3_WAIT10;
					end
					
					2'b10: begin
						state <= S_M3_WAIT20;
						address <= address - 18'd1;
					end
					
					default: state <= previous_state;
				endcase
				waiting_fetches <= 2'b0;
			end 
			fill <= 1'b0;
		end
		
		S_M3_WAIT10: begin
			state <= S_M3_WAIT11;
		end
		
		S_M3_WAIT11: begin
			state <= S_M3_WAIT12;
		end
		
		S_M3_WAIT12: begin
			read_buffer[47:16] <= read_buffer[31:0];
			read_buffer[15:0] <= read_data;
			buffer_index <= buffer_index + 6'd16;
			fill <= 1'b0;
			state <= previous_state;
		end
		
		S_M3_WAIT20: begin
			address <= address + 18'd1;
			state <= S_M3_WAIT21;
		end
		
		S_M3_WAIT21: begin
			state <= S_M3_WAIT22;
		end
		
		S_M3_WAIT22: begin
			read_buffer[47:16] <= read_buffer[31:0];
			read_buffer[15:0] <= read_data;
			buffer_index <= buffer_index + 6'd16;
			fill <= 1'b0;
			state <= S_M3_WAIT23;
		end
		
		S_M3_WAIT23: begin
			read_buffer[47:16] <= read_buffer[31:0];
			read_buffer[15:0] <= read_data;
			buffer_index <= buffer_index + 6'd16;		
			state <= previous_state;
		end	
		
		default: state <= S_M3_IDLE;
		endcase
	end
end

endmodule