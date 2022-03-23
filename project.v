/*
Copyright by Henry Ko and Nicola Nicolici
Developed for the Digital Systems Design course (COE3DQ4)
Department of Electrical and Computer Engineering
McMaster University
Ontario, Canada
*/

`timescale 1ns/100ps
`default_nettype none

`include "define_state.h"

// This is the top module
// It connects the UART, SRAM and VGA together.
// It gives access to the SRAM for UART and VGA
module project (
		/////// board clocks                      ////////////
		input logic CLOCK_50_I,                   // 50 MHz clock

		/////// pushbuttons/switches              ////////////
		input logic[3:0] PUSH_BUTTON_I,           // pushbuttons
		input logic[17:0] SWITCH_I,               // toggle switches

		/////// 7 segment displays/LEDs           ////////////
		output logic[6:0] SEVEN_SEGMENT_N_O[7:0], // 8 seven segment displays
		output logic[8:0] LED_GREEN_O,            // 9 green LEDs

		/////// VGA interface                     ////////////
		output logic VGA_CLOCK_O,                 // VGA clock
		output logic VGA_HSYNC_O,                 // VGA H_SYNC
		output logic VGA_VSYNC_O,                 // VGA V_SYNC
		output logic VGA_BLANK_O,                 // VGA BLANK
		output logic VGA_SYNC_O,                  // VGA SYNC
		output logic[9:0] VGA_RED_O,              // VGA red
		output logic[9:0] VGA_GREEN_O,            // VGA green
		output logic[9:0] VGA_BLUE_O,             // VGA blue
		
		/////// SRAM Interface                    ////////////
		inout wire[15:0] SRAM_DATA_IO,            // SRAM data bus 16 bits
		output logic[17:0] SRAM_ADDRESS_O,        // SRAM address bus 18 bits
		output logic SRAM_UB_N_O,                 // SRAM high-byte data mask 
		output logic SRAM_LB_N_O,                 // SRAM low-byte data mask 
		output logic SRAM_WE_N_O,                 // SRAM write enable
		output logic SRAM_CE_N_O,                 // SRAM chip enable
		output logic SRAM_OE_N_O,                 // SRAM output logic enable
		
		/////// UART                              ////////////
		input logic UART_RX_I,                    // UART receive signal
		output logic UART_TX_O                    // UART transmit signal
);
	
logic resetn;
//logic toggle;
logic [15:0] q_a;
logic [15:0] q_b;
logic [7:0] address_a;
logic wren_a;
logic [15:0] write_data_a;
logic continue_M3;

//Test
logic [15:0]R, G, B;
logic [31:0]ODD_OUT, EVEN_OUT;
logic [31:0]U_OUT, V_OUT;


top_state_type top_state;

// For Push button
logic [3:0] PB_pushed;

// For VGA SRAM interface
logic VGA_enable;
logic [17:0] VGA_base_address;
logic [17:0] VGA_SRAM_address;

// For SRAM
logic [17:0] SRAM_address;
logic [15:0] SRAM_write_data;
logic SRAM_we_n;
logic [15:0] SRAM_read_data;
logic SRAM_ready;

// For UART SRAM interface
logic UART_rx_enable;
logic UART_rx_initialize;
logic [17:0] UART_SRAM_address;
logic [15:0] UART_SRAM_write_data;
logic UART_SRAM_we_n;
logic [25:0] UART_timer;

//For Milestone 3 SRAM interface
logic [17:0] M3_SRAM_address;
logic startM3;
logic first_M3_cycle;
logic error;
logic [15:0] M2_read_input; 
logic [7:0] M2_address_a;
logic [7:0] M3_address_a;
logic endM3;

//For Milestone 2 SRAM interface
logic [17:0] M2_SRAM_address;
logic [15:0] M2_SRAM_write_data;
logic M2_SRAM_we_n;
logic startM2;
logic endM2;
logic address_selector;

// For Milestone 1 SRAM interface
logic [17:0] M1_SRAM_address;
logic [15:0] M1_SRAM_write_data;
logic M1_SRAM_we_n;
logic startM1;
logic endM1;
logic first_M1_cycle;
logic first_M2_cycle;
logic DP_RAM_enable;
logic [6:0] value_7_segment [7:0];

// For error detection in UART
logic [3:0] Frame_error;

// For disabling UART transmit
assign UART_TX_O = 1'b1;

assign resetn = ~SWITCH_I[17] && SRAM_ready;

// Push Button unit
PB_Controller PB_unit (
	.Clock_50(CLOCK_50_I),
	.Resetn(resetn),
	.PB_signal(PUSH_BUTTON_I),	
	.PB_pushed(PB_pushed)
);

// VGA SRAM interface
VGA_SRAM_interface VGA_unit (
	.Clock(CLOCK_50_I),
	.Resetn(resetn),
	.VGA_enable(VGA_enable),
   
	// For accessing SRAM
	.SRAM_base_address(VGA_base_address),
	.SRAM_address(VGA_SRAM_address),
	.SRAM_read_data(SRAM_read_data),
   
	// To VGA pins
	.VGA_CLOCK_O(VGA_CLOCK_O),
	.VGA_HSYNC_O(VGA_HSYNC_O),
	.VGA_VSYNC_O(VGA_VSYNC_O),
	.VGA_BLANK_O(VGA_BLANK_O),
	.VGA_SYNC_O(VGA_SYNC_O),
	.VGA_RED_O(VGA_RED_O),
	.VGA_GREEN_O(VGA_GREEN_O),
	.VGA_BLUE_O(VGA_BLUE_O)
);

// UART SRAM interface
UART_SRAM_interface UART_unit(
	.Clock(CLOCK_50_I),
	.Resetn(resetn), 
   
	.UART_RX_I(UART_RX_I),
	.Initialize(UART_rx_initialize),
	.Enable(UART_rx_enable),
   
	// For accessing SRAM
	.SRAM_address(UART_SRAM_address),
	.SRAM_write_data(UART_SRAM_write_data),
	.SRAM_we_n(UART_SRAM_we_n),
	.Frame_error(Frame_error)
);

// SRAM unit
SRAM_Controller SRAM_unit (
	.Clock_50(CLOCK_50_I),
	.Resetn(~SWITCH_I[17]),
	.SRAM_address(SRAM_address),
	.SRAM_write_data(SRAM_write_data),
	.SRAM_we_n(SRAM_we_n),
	.SRAM_read_data(SRAM_read_data),		
	.SRAM_ready(SRAM_ready),
		
	// To the SRAM pins
	.SRAM_DATA_IO(SRAM_DATA_IO),
	.SRAM_ADDRESS_O(SRAM_ADDRESS_O),
	.SRAM_UB_N_O(SRAM_UB_N_O),
	.SRAM_LB_N_O(SRAM_LB_N_O),
	.SRAM_WE_N_O(SRAM_WE_N_O),
	.SRAM_CE_N_O(SRAM_CE_N_O),
	.SRAM_OE_N_O(SRAM_OE_N_O)
);


//Milestone 1 module
milestone1 mile1(
		.CLOCK_50_I(CLOCK_50_I),                   
		.resetn(resetn),								
		.read_data(SRAM_read_data),
		.startmilestone1(startM1),					
		.address(M1_SRAM_address),
		.write_data(M1_SRAM_write_data),
		.we_n(M1_SRAM_we_n),
		.endmilestone1(endM1),
		.R_OUT(R),
		.G_OUT(G),
		.B_OUT(B),
		.RGB_MACODD(ODD_OUT),
		.RGB_MACEVEN(EVEN_OUT),
		.U_MAC(U_OUT),
		.V_MAC(V_OUT)
);

//Milestone 2 module
milestone2 mile2(
		.CLOCK_50_I(CLOCK_50_I),
		.resetn(resetn),				
		.read_data(M2_read_input),			
		.startmilestone2(startM2),	
		.address(M2_SRAM_address),
		.RAM_address(M2_address_a),
		.DP_RAM(DP_RAM_enable),
		.write_data(M2_SRAM_write_data),
		.we_n(M2_SRAM_we_n),
		.endmilestone2(endM2),
		.continue_milestone3(continue_M3),
		.address_flag(address_selector)
);

always_ff @(posedge CLOCK_50_I) begin
	M2_read_input <= q_a;
end

assign address_a = (DP_RAM_enable == 1'b1 ) ? M2_address_a: M3_address_a;

//Milestone 3 module
milestone3 mile3(
	.CLOCK_50_I(CLOCK_50_I),
	.resetn(resetn),
	.read_data(SRAM_read_data),							
	.start_reading(continue_M3),					
	.startmilestone3(startM3),
	.pause(address_selector),
	.address(M3_SRAM_address),
	.error(error),
	.endM3(endM3),
	.DP_write_data(write_data_a),
	.DP_we_n(wren_a),
	.DP_RAM_address(M3_address_a)
);

//DP RAM for M3
M3_Interface_RAM integrator_RAM(
	.address_a (address_a),
	.address_b (8'b0),
	.clock (CLOCK_50_I),
	.data_a (write_data_a),
	.data_b (16'b0),
	.wren_a (wren_a),
	.wren_b (1'b0),
	.q_a (q_a),
	.q_b (q_b)
);

always @(posedge CLOCK_50_I or negedge resetn) begin
	if (~resetn) begin
		top_state <= S_IDLE;
		
		UART_rx_initialize <= 1'b0;
		UART_rx_enable <= 1'b0;
		UART_timer <= 26'd0;
		
		VGA_enable <= 1'b1;
		first_M1_cycle <= 1'b1;
		first_M2_cycle <= 1'b1;
		first_M3_cycle <= 1'b1;
		startM1 <= 1'b0;
		startM2 <= 1'b0;
		startM3 <= 1'b0;

	end else begin
		UART_rx_initialize <= 1'b0; 
		UART_rx_enable <= 1'b0; 
		
		// Timer for timeout on UART
		// This counter reset itself every time a new data is received on UART
		if (UART_rx_initialize | ~UART_SRAM_we_n) UART_timer <= 26'd0;
		else UART_timer <= UART_timer + 26'd1;

		case (top_state)
		S_IDLE: begin
			VGA_enable <= 1'b1;
			first_M1_cycle <= 1'b1;
			first_M2_cycle <= 1'b1;
			first_M3_cycle <= 1'b1;
			startM1 <= 1'b0;
			startM2 <= 1'b0;
			startM3 <= 1'b0;
			//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
			//top_state <= S_M3; //Uncomment for modelsim testing.
			//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
			if (~UART_RX_I | PB_pushed[0]) begin
				// UART detected a signal, or PB0 is pressed
				UART_rx_initialize <= 1'b1;
				
				VGA_enable <= 1'b0;
								
				top_state <= S_ENABLE_UART_RX;
			end
		end
		
		S_ENABLE_UART_RX: begin
			// Enable the UART receiver
			UART_rx_enable <= 1'b1;
			top_state <= S_WAIT_UART_RX;
		end
		S_WAIT_UART_RX: begin
			if ((UART_timer == 26'd49999999) && (UART_SRAM_address != 18'h00000)) begin
				// Timeout for 1 sec on UART for detecting if file transmission is finished
				UART_rx_initialize <= 1'b1;		 				
				top_state <= S_M3;
			end
		end
		
		S_M3: begin
			if(first_M3_cycle) begin
				startM3 <= 1'b1;
				first_M3_cycle <= 1'b0;
			end else begin
				startM3 <= 1'b0;
			end
			
			if(endM3 == 1'b1) begin
				top_state <= S_M2;
			end
		end
		
		S_M2: begin
			if (first_M2_cycle) begin
				startM2 <= 1'b1;
				first_M2_cycle <= 1'b0;
			end else begin
				startM2 <= 1'b0;
			end
			
			if(endM2 == 1'b1) begin
				top_state <= S_M1;
			end
		end
		
		S_M1: begin
//			toggle <= 1'b1;
			if (first_M1_cycle) begin
				startM1 <= 1'b1;
				first_M1_cycle <= 1'b0;
			end else begin
				startM1 <= 1'b0;
			end
			
			if (endM1 == 1'b1) begin
				VGA_enable <= 1'b1;
				top_state <= S_IDLE;
			end
		end
		
		default: top_state <= S_IDLE;
		endcase
	end
end

assign VGA_base_address = 18'd146944;

// Give access to SRAM for UART and VGA at appropriate time
assign SRAM_address = (top_state == S_IDLE) ? VGA_SRAM_address : ((top_state == S_ENABLE_UART_RX) | (top_state == S_WAIT_UART_RX)) ? UART_SRAM_address :
						(top_state == S_M1) ? M1_SRAM_address : (address_selector == 1'b1) ? M2_SRAM_address : M3_SRAM_address; 

assign SRAM_write_data = (top_state == S_M1) ? M1_SRAM_write_data : (top_state == S_M2) ? M2_SRAM_write_data : UART_SRAM_write_data;

assign SRAM_we_n = ((top_state == S_ENABLE_UART_RX) | (top_state == S_WAIT_UART_RX)) ? UART_SRAM_we_n :
						(top_state == S_M1) ? M1_SRAM_we_n : (top_state == S_M2) ? M2_SRAM_we_n : 1'b1;

// 7 segment displays
convert_hex_to_seven_segment unit7 (
	.hex_value(SRAM_read_data[15:12]), 
	.converted_value(value_7_segment[7])
);

convert_hex_to_seven_segment unit6 (
	.hex_value(SRAM_read_data[11:8]), 
	.converted_value(value_7_segment[6])
);

convert_hex_to_seven_segment unit5 (
	.hex_value(SRAM_read_data[7:4]), 
	.converted_value(value_7_segment[5])
);

convert_hex_to_seven_segment unit4 (
	.hex_value(SRAM_read_data[3:0]), 
	.converted_value(value_7_segment[4])
);

convert_hex_to_seven_segment unit3 (
	.hex_value({2'b00, SRAM_address[17:16]}), 
	.converted_value(value_7_segment[3])
);

convert_hex_to_seven_segment unit2 (
	.hex_value(SRAM_address[15:12]), 
	.converted_value(value_7_segment[2])
);

convert_hex_to_seven_segment unit1 (
	.hex_value(SRAM_address[11:8]), 
	.converted_value(value_7_segment[1])
);

convert_hex_to_seven_segment unit0 (
	.hex_value(SRAM_address[7:4]), 
	.converted_value(value_7_segment[0])
);

assign   
   SEVEN_SEGMENT_N_O[0] = value_7_segment[0],
   SEVEN_SEGMENT_N_O[1] = value_7_segment[1],
   SEVEN_SEGMENT_N_O[2] = value_7_segment[2],
   SEVEN_SEGMENT_N_O[3] = value_7_segment[3],
   SEVEN_SEGMENT_N_O[4] = value_7_segment[4],
   SEVEN_SEGMENT_N_O[5] = value_7_segment[5],
   SEVEN_SEGMENT_N_O[6] = value_7_segment[6],
   SEVEN_SEGMENT_N_O[7] = value_7_segment[7];

//assign LED_GREEN_O = {resetn, VGA_enable, ~SRAM_we_n, Frame_error, top_state};
assign LED_GREEN_O = {8'b0, error};

endmodule
