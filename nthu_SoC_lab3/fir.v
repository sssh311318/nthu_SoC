`timescale 1ns / 1ps

module fir
#(
    parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num  = 11
)
(
    //AXI lite
    // coef write address
    output reg                      awready,
    input wire                      awvalid,
    input wire [pADDR_WIDTH-1:0]    awaddr,
    // coef write data
    output reg                      wready,
    input wire                      wvalid,
    input wire signed [pDATA_WIDTH-1:0]    wdata,
    // coef read address
    output reg                      arready,
    input wire                      arvalid,
    input wire [pADDR_WIDTH-1:0]    araddr,
    //coef read data
    input wire                      rready,
    output reg                      rvalid,
    output reg signed [pDATA_WIDTH-1:0]    rdata,
    //AXI stream
    //data
    input wire                      ss_tvalid,
    input wire                      ss_tlast,
    input wire signed [pDATA_WIDTH-1:0]    ss_tdata,
    output reg                      ss_tready,
    //check
    input  wire                     sm_tready, 
    output reg                     sm_tvalid, 
    output reg                     sm_tlast,
    output reg signed [(pDATA_WIDTH-1):0] sm_tdata, 

    // bram for tap RAM
    output reg [3:0]                tap_WE,
    output reg                      tap_EN,
    output reg signed [(pDATA_WIDTH-1):0]  tap_Di,
    output reg [(pADDR_WIDTH-1):0]  tap_A,
    input  wire signed [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output reg [3:0]                data_WE,
    output reg                      data_EN,
    output reg signed [(pDATA_WIDTH-1):0]  data_Di,
    output reg [(pADDR_WIDTH-1):0]  data_A,
    input  wire signed [(pDATA_WIDTH-1):0] data_Do,

    // clk & reset
    input  wire           axis_clk,
    input  wire           axis_rst_n
);
//tap_num & program length//////////////////
reg [9:0] length;
reg [31:0] ap;
reg bram_ready;
always @(posedge axis_clk or negedge axis_rst_n)begin
    if(!axis_rst_n)begin
        awready <= 0;
        wready <= 0;
        arready <= 0;
        rvalid <= 0;
        tap_EN <= 0;
        tap_WE <= 4'b0;
        // set ap_idle = 1, ap_done = 0, ap_start = 0
        ap[31:0] <= 32'h0000_0005;
    end else begin
        // set ready high
        if(awvalid && wvalid)begin
            awready <= 1'b1;
            wready <= 1'b1;
        end
        if(wvalid && wready && awvalid && awready) begin
            // write the coef
            if(awaddr == 12'h30)begin
                length = wdata;
            end else if(awaddr == 12'h2c) begin
                if(wdata == 32'h0000_0001) begin
                    // set ap_idle = 0, ap_done = 0, ap_start = 0
                    if(ap == 32'h0000_0004)begin
                        ap <= 32'h0000_0004;
                    end else begin
                        if(ss_tlast)begin
                            ap[31:0] <= 32'h0000_0002;
                        end else begin
                            ap[31:0] <= 32'h0000_0000;
                        end
                    end

                end
            end else begin
                tap_WE <= 4'b1111;
                tap_EN <= 1'b1;
                tap_A <= awaddr;
                tap_Di <= wdata;
                awready <= 1'b0;
                wready <= 1'b0;
            end
        end
        // check
        if(arvalid)begin
            arready <= 1'b1;
            tap_WE <= 4'b0000;
        end
        if(arready && arvalid)begin
            if(awaddr == 12'h2c) begin
                if(ap == 32'h0000_0004)begin
                    // set ap_idle = 1, ap_done = 1, ap_start = 0
                    ap[31:0] <= 32'h0000_0004;
                end
                bram_ready <= 1;
                arready <= 1'b0;
                if(bram_ready)begin
                    rdata <= ap;
                    rvalid <= 1'b1;
                    bram_ready <= 0;
                end

            end else begin
                tap_EN <= 1'b1;
                tap_A <= araddr;
                bram_ready <= 1;
                arready <= 1'b0;
                if(bram_ready)begin
                    rdata <= tap_Do;
                    rvalid <= 1'b1;
                    bram_ready <= 0;
                end
            end
        end
        if(rvalid && rready)begin
            rvalid <= 1'b0;
            arready <= 1'b0;
        end
    end
end
/////coef correct ////////////

// AXI stream data in FIR///////////////////////////

// record the address where new data need to be stored
reg [pADDR_WIDTH-1:0] data_index;       //[11:0]
// fir data address
reg [pADDR_WIDTH-1:0] fir_data_index;   //[11:0]
// fir final data address if i have count i dont need this
//reg [pADDR_WIDTH-1:0] end_data_index;   //[11:0]
// coef address
reg [pADDR_WIDTH-1:0] coef_index;       //[11:0]
// fir ready for next new data
reg fir_ready;

// note data read from BRAM 
reg [2:0] state;
// whitch data
reg [3:0] count;
reg [9:0] tcount;

// store new data in BRAM, get both address, and find 11 or not
reg [pDATA_WIDTH-1:0] acc;
reg [3:0] acc_count;
always @(posedge axis_clk or negedge axis_rst_n)begin
    if(!axis_rst_n)begin
        data_index <= 12'h00;
        coef_index <= 12'h00;
        fir_data_index <= 12'h00;
        fir_ready <= 1;
        ss_tready <= 0;
        count <= 0;
        //end_data_index <= 12'h00;
        // state 0
        state <= 2'b00;
        acc <= 0;
        acc_count <= 0;
        tcount <= 0;
    end else begin
        if(!ap[2])begin
            // as acc available
            if(state == 0)begin
                if(ss_tvalid)begin
                    ss_tready <= 1'b1;
                end
                if(ss_tvalid && ss_tready)begin
                    // store this new data in BRAM and get it
                    data_A <= data_index;
                    data_Di <= ss_tdata;
                    data_EN <= 1'b1;
                    data_WE <= 4'b1111;    
                    ss_tready <= 0;

                    // ready for the next data address
                    data_index <= data_index + 4;
                    if(data_index == 12'h28)begin
                        data_index <= 12'h00;
                    end

                    // get start data address
                    fir_data_index <= data_index;
                    // get the first coef address
                    coef_index <= 12'h00;

                    //get coef
                    tap_WE <= 4'b0000;
                    tap_A <= 12'h00;
                    tap_EN <= 1'b1;


                    // mode11
                    if(count != 11)begin
                        count <= count + 1;
                    end
                    tcount <= tcount + 1;

                    if(tcount == 600)begin
                        ap <= 32'h0000_0004;
                    end
                    acc <= 0;
                    acc_count <= 0;
                    state <= 1;

                end
            end
        end
    end
end

//get coef and data //////////////////////////////////////
reg acc_state;
always @(posedge axis_clk or negedge axis_rst_n)begin
    if(!axis_rst_n)begin
        acc <= 0;
    end else begin
        if(!ap[2])begin
            if(state == 1)begin
                if(acc_state == 1)begin
                    state <= 2;
                    acc_state <= 0;
                end else begin
                    acc_state <= 1;
                    // read coef from BRAM
                    tap_WE <= 4'b0000;
                    tap_A <= coef_index;
                    tap_EN <= 1'b1;

                    // read data from BRAM
                    data_WE <= 4'b0000;
                    data_A <= fir_data_index;
                    data_EN <= 1'b1;
                end
            end else if(state == 2) begin
                acc_count <= acc_count + 1; 
                acc <= tap_Do * data_Do + acc;
                state <= 3;
            end
        end
    end
end

always @(posedge axis_clk)begin
    if(state == 3)begin
        if(count == 11)begin
            if(count == acc_count)begin
                state <= 4;
            end else begin
                // get next address of coef and data
                coef_index <= coef_index + 4;
                if(fir_data_index == 12'h00)begin
                    fir_data_index <= 12'h28;
                end else begin
                    fir_data_index <= fir_data_index - 4;
                end
                state <= 1;
            end
        end else begin
            //if(fir_data_index == 12'h00)begin
            if(count == acc_count)begin
                state <= 4;
            end else begin
                // get next address of coef and data
                coef_index <= coef_index + 4;
                fir_data_index <= fir_data_index - 4;
                state <= 1;
            end 
            
        end
    end
end

always @(posedge axis_clk )begin
    if(state == 4)begin
        sm_tdata <= acc;
        sm_tvalid <= 1'b1;
        if(sm_tready && sm_tvalid)begin
            state <= 0;
            sm_tvalid <= 0;
        end
        if(tcount == 600)begin
            //sm_tvalid <= 0;
        end
    end
end

endmodule
