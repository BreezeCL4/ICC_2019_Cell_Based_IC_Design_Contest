// Topic: ICC 2019 IoT Data Filtering (IOTDF)
// Author: Andrew Chang
// Date: 2025.07.14
// Version: v1.0
// Description: IOTDF  supports 7 functional modes defined by the contest, processing 96 IoT sensor data inputs (128 bits each) via streaming, and outputs processed results based on the selected function.
// Design: IOTDF.v can be seperated into 3 parts, FSM, Parsing, Output..
// Notes:
//  * Pipeline-friendly: Inputs are received and assembled serially, processing 1 byte per clock.
//  * Flexible design: Can support extension to more functions by adding more fn_sel cases.
//  * Clear separation: FSM, parsing, and output logic are well-isolated, following good RTL style.

`timescale 1ns/10ps

`define MAX(a,b) (((a) > (b)) ? (a) : (b))
`define MIN(a,b) (((a) < (b)) ? (a) : (b))

module IOTDF ( 
    input clk
    ,input rst
    ,input  in_en
    ,input[7:0] iot_in
    ,input[2:0] fn_sel
    ,output reg busy
    ,output reg valid
    ,output reg [127:0] iot_out
);

    localparam F1 = 3'b001;  // Max in group
    localparam F2 = 3'b010;  // Min in group
    localparam F3 = 3'b011;  // Average in group
    localparam F4 = 3'b100;  // Extract in Range
    localparam F5 = 3'b101;  // Exclude in Range
    localparam F6 = 3'b110;  // Peak Max
    localparam F7 = 3'b111;  // Peak Min
    
    //  These thresholds are used for F4 (inclusive range filter) and F5 (exclusive range filter).
    localparam [127:0] F4_LOW  = 128'h6FFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
    localparam [127:0] F4_HIGH = 128'hAFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
    localparam [127:0] F5_LOW  = 128'h7FFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
    localparam [127:0] F5_HIGH = 128'hBFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
    
    localparam MAX_BYTE_CNT = 16;
    localparam MAX_DATA_CNT = 96;
    localparam MAX_ROUND_DATA_CNT = 8;
    localparam MAX_ROUND_CNT = 12;
    localparam FIFO_WIDTH = 119;
    localparam DATA_WIDTH = 127;
    
    reg ex_valid;
    reg peak_valid;
    reg save_data; // Flag to store a 128-bit data word
    reg is_not_first_peak;
    reg [DATA_WIDTH:0] curr_buf;
    reg [DATA_WIDTH + 4:0] temp_buf; // Temporary buffer for min/max/avg/sum
    reg [DATA_WIDTH:0] keep_buf;
    reg [3:0] byte_cnt; // Max: 16
    reg [6:0] data_cnt; // Max: 96
    reg [3:0] round_data_cnt; // Max: 8
    reg [3:0] round_cnt; // Max: 12
    reg [2:0] fn_selection;
    
    wire data_ready;
    
    assign data_ready = save_data;

// FSM
always @(posedge clk or posedge rst) begin
    if (rst) begin
        busy <= 0;
        valid <= 0;
        ex_valid <= 0;
        peak_valid <= 0;
        is_not_first_peak <= 0;
        iot_out <= 0;
        curr_buf <= 0;
        keep_buf <= 0;
        save_data <= 0;
        data_cnt <= 0;
        byte_cnt <= 0;
        round_data_cnt <= 0;
        round_cnt <= 0;
        fn_selection <= 0;
    end else begin
        busy = (data_cnt >= MAX_DATA_CNT);
        valid <= 0;
        peak_valid <= 0;
        save_data <= 0;
        
        if (in_en && !busy) begin
            curr_buf <= {curr_buf[FIFO_WIDTH:0], iot_in};
            byte_cnt <= byte_cnt + 1;
            
            if (byte_cnt == MAX_BYTE_CNT - 1) begin
                save_data <= 1; // Save data in next clk
                byte_cnt <= 0;
            end
            
            if ((data_cnt == 0) && (byte_cnt == 1)) fn_selection <= fn_sel;
        end
        
        if (data_ready) begin
            data_cnt <= (data_cnt == MAX_DATA_CNT - 1) ? 0 : data_cnt + 1;
            round_data_cnt <= (round_data_cnt == MAX_ROUND_DATA_CNT - 1) ? 0 : round_data_cnt + 1;
            round_cnt <= (round_data_cnt == MAX_ROUND_DATA_CNT - 1) ? round_cnt + 1: round_cnt;
            if (round_cnt == MAX_ROUND_CNT - 1) round_cnt <= 0;
            
            case (fn_selection)
                F1, F2, F3: valid <= (round_data_cnt == MAX_ROUND_DATA_CNT - 1);
                F4, F5: valid <= ex_valid;
                F6, F7: valid <= peak_valid;
                default: valid <= 0;
            endcase
            
            if ((fn_selection == F6) || (fn_selection == F7)) begin
                if (data_cnt == 0) begin
                    if (!is_not_first_peak) is_not_first_peak <= 1;
                end else if (data_cnt == MAX_DATA_CNT - 1) begin
                    if (is_not_first_peak) is_not_first_peak <= 0;
                end
            end
        end
    end
end

// Data Parsing
always @(posedge clk or posedge rst) begin
    if (rst) begin
        temp_buf <= 0;
        keep_buf <= 0;
    end else if (data_ready) begin
        temp_buf <= curr_buf;
        
        // Process Func
        case (fn_selection)
            F1: begin
                if (round_data_cnt != 0) begin temp_buf <= `MAX(temp_buf, curr_buf); end
            end F2: begin
                if (round_data_cnt != 0) begin temp_buf <= `MIN(temp_buf, curr_buf); end
            end F3: begin
                if (round_data_cnt == 0) begin
                    temp_buf <= curr_buf;
                end else if (round_data_cnt != MAX_ROUND_DATA_CNT - 1) begin
                    temp_buf <= temp_buf + curr_buf;
                end else begin
                    temp_buf <= (temp_buf + curr_buf) >> 3; // 8 data per round
                end
            end F4: begin
                ex_valid <= ((curr_buf >= F4_LOW) && (curr_buf <  F4_HIGH));
            end F5: begin
                ex_valid <= !((curr_buf >= F5_LOW) && (curr_buf <  F5_HIGH));
            end F6: begin
                if (!is_not_first_peak) keep_buf <= curr_buf;
                if (round_data_cnt != 0) begin temp_buf <= `MAX(temp_buf, curr_buf); end
                if (round_data_cnt == MAX_ROUND_DATA_CNT - 1) begin
                    if (keep_buf < `MAX(temp_buf, curr_buf)) begin 
                        keep_buf <= `MAX(temp_buf, curr_buf);
                        peak_valid <= 1;
                    end
                end
            end F7: begin
                if (!is_not_first_peak) keep_buf <= curr_buf;
                if (round_data_cnt != 0) begin temp_buf <= `MIN(temp_buf, curr_buf); end
                if (round_data_cnt == MAX_ROUND_DATA_CNT - 1) begin
                    if (keep_buf > `MIN(temp_buf, curr_buf)) begin 
                        keep_buf <= `MIN(temp_buf, curr_buf);
                        peak_valid <= 1;
                    end
                end
            end default: begin
                ; // Prevent dummy
            end
        endcase
    end
end

// Data Out
always @(posedge clk or posedge rst) begin
    if (rst) begin
        iot_out <= 0;
    end else if (data_ready) begin
//        iot_out <= 0;
        case (fn_selection)
            F1: begin
                if (round_data_cnt == MAX_ROUND_DATA_CNT - 1) iot_out <= `MAX(temp_buf, curr_buf);
            end F2: begin
                if (round_data_cnt == MAX_ROUND_DATA_CNT - 1) iot_out <= `MIN(temp_buf, curr_buf);
            end F3: begin
                if (round_data_cnt == MAX_ROUND_DATA_CNT - 1) iot_out <= (((temp_buf) + (curr_buf)) >> 3);
            end F4: begin
                if ((curr_buf >= F4_LOW) && (curr_buf <  F4_HIGH)) iot_out <= curr_buf;
            end F5: begin
                if (!((curr_buf >= F5_LOW) && (curr_buf <  F5_HIGH))) iot_out <= curr_buf;
            end F6: begin
                if ((round_data_cnt == MAX_ROUND_DATA_CNT - 1) && (keep_buf < `MAX(temp_buf, curr_buf))) iot_out <= `MAX(temp_buf, curr_buf);
            end F7: begin
                if ((round_data_cnt == MAX_ROUND_DATA_CNT - 1) && (keep_buf > `MIN(temp_buf, curr_buf))) iot_out <= `MIN(temp_buf, curr_buf);
            end default: begin
                iot_out <= 0;
            end
        endcase
    end
end
endmodule
