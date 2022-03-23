

# add waves to waveform
add wave Clock_50
#add wave -divider {some label for my divider}
add wave uut/SRAM_we_n
add wave -hexadecimal uut/SRAM_write_data
add wave -hexadecimal uut/SRAM_read_data
add wave -unsigned uut/SRAM_address
add wave -decimal uut/top_state

# Waves for Milestone 1
#add wave -hexadecimal uut/R
#add wave -hexadecimal uut/G
#add wave -hexadecimal uut/B
#add wave -hexadecimal uut/ODD_OUT
#add wave -hexadecimal uut/EVEN_OUT
#add wave -decimal uut/U_OUT
#add wave -decimal uut/V_OUT
#add wave -decimal uut/mile1/state
#add wave -unsigned uut/mile1/column_count

#Waves for Milestone 2
add wave -decimal uut/mile2/state
#add wave -decimal uut/mile2/MAC
#add wave -decimal uut/mile2/MAC_buffer
#add wave -decimal uut/mile2/RAM1_write_data1
#add wave -decimal uut/mile2/RAM1_write_data2
#add wave -unsigned uut/mile2/RAM1_address1
#add wave -unsigned uut/mile2/RAM1_address2
#add wave -decimal uut/mile2/RAM2_write_data1
#add wave -decimal uut/mile2/RAM2_write_data2
#add wave -unsigned uut/mile2/RAM2_address1
#add wave -unsigned uut/mile2/RAM2_address2
#add wave -hexadecimal uut/mile2/C_read_data1
#add wave -hexadecimal uut/mile2/C_read_data2
#add wave -decimal uut/mile2/RAM1_read_data1
#add wave -decimal uut/mile2/RAM1_read_data2
#add wave -decimal uut/mile2/RAM2_read_data1
#add wave -decimal uut/mile2/RAM2_read_data2
#add wave -unsigned uut/mile2/SRAM_address/write_matrix_offset
#add wave -unsigned uut/mile2/SRAM_address/matrix_offset
#add wave -decimal uut/mile2/megastateA_counter
#add wave -decimal uut/mile2/SRAM_operation_complete
#add wave -decimal uut/mile2/SRAM_address/first_cycle

#Waves for Milestone 3
add wave -decimal uut/mile3/enable
add wave -decimal uut/mile3/state
add wave -hexadecimal uut/mile3/read_buffer
add wave -unsigned uut/mile3/buffer_index
add wave -unsigned uut/mile3/element_count
#add wave -decimal uut/mile3/error
#add wave -decimal uut/mile3/var_number
#add wave -decimal uut/mile3/variable_shift/diagonal_index
add wave -decimal uut/mile3/variable_shift/result
#add wave -decimal uut/mile3/variable_shift/address_a
add wave -decimal uut/address_a
add wave -decimal uut/q_a
#add wave -decimal uut/DP_RAM_enable
add wave -decimal uut/M2_read_input
add wave -decimal uut/mile3/read_shift
add wave -decimal uut/mile3/timer1
add wave -decimal uut/mile3/timer2
add wave -decimal uut/mile3/fill