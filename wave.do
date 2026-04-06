onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/clk
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/rst
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/config_valid
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/config_ready
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/config_data_in
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/config_keep
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/config_last
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/weight_ram_wr_data
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/weight_ram_wr_en
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/threshold_ram_wr_data
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/threshold_ram_wr_en
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/parser_ready
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/empty
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/fifo_wr_en_r
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/msg_type_r
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/layer_id_r
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/total_bytes_r
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/bytes_per_neuron_r
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/w_empty
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/t_empty
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/w_alm_full
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/t_alm_full
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/w_rd_en
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/w_wr_en
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/t_rd_en
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/t_wr_en
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/packer_empty
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/all_packers_empty
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/active_stream_empty
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/state_r
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/next_state
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/rd_count_r
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/next_rd_count
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/count_r
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/next_count
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/byte_idx_r
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/next_byte_idx
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/pad_count_r
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/next_pad_count
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/last_rd_r
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/next_last_rd
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/buffer_wr_en
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/fifo_rd_en
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/data
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/w_byte_data
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/bytes_per_word
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/pad_remainder
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/bytes_to_pad
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/pad_en
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/packer_rd_en
add wave -noupdate -expand -group cfm /bnn_fcc_uvm_tb/dut/config_manager/packer_rd_data
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/clk
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/rst
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/weight_wr_en
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/threshold_wr_en
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/ram_weight_wr_en
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/ram_threshold_wr_en
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/weight_addr_out
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/threshold_addr_out
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/done
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/state_r
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/next_state
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/w_word_count_r
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/next_w_word_count
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/w_neuron_r
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/next_w_neuron
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/w_total_cycles_r
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/next_w_total_cycles
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/w_bank_addr_r
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/next_w_bank_addr
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/t_neuron_r
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/next_t_neuron
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/t_total_cycles_r
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/next_t_total_cycles
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/t_bank_addr_r
add wave -noupdate -expand -group cfc0 /bnn_fcc_uvm_tb/dut/bnn_main/u_layer_1/u_cfc/next_t_bank_addr
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {380384500 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {380384100 ps} {380385100 ps}
