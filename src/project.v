/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_uwasic_onboarding_evelynn_lu (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
  assign uio_oe = 8'hFF; // Set all IOs to output

  wire [7:0] en_reg_out_7_0;
  wire [7:0] en_reg_out_15_8;
  wire [7:0] en_reg_pwm_7_0;
  wire [7:0] en_reg_pwm_15_8;
  wire [7:0] pwm_duty_cycle;

  pwm_peripheral pwm_peripheral_inst (
    .clk(clk),
    .rst_n(rst_n),
    .en_reg_out_7_0(en_reg_out_7_0),
    .en_reg_out_15_8(en_reg_out_15_8),
    .en_reg_pwm_7_0(en_reg_pwm_7_0),
    .en_reg_pwm_15_8(en_reg_pwm_15_8),
    .pwm_duty_cycle(pwm_duty_cycle),
    .out({uio_out, uo_out})
  );
  //SYNCHRONIZE Sclk, COPI, Cs --> Sclk _ync2, COPI_sync2, nCs_sync2;
  reg Sclk_sync1, Sclk_sync2; //Sclk = ui_in[0]
  reg COPI_sync1, COPI_sync2; //COPI = ui_in[1]
  reg nCs_sync1, nCs_sync2, nCs_prev; //Cs = ui_in[2]

  reg Sclk_sync_prev;
  always@(posedge clk)begin
    Sclk_sync1 <= ui_in[0];
    Sclk_sync2 <= Sclk_sync1;
    Sclk_sync_prev <= Sclk_sync2; //stores previous Sclk synced

    COPI_sync1 <= ui_in[1];
    COPI_sync2 <= COPI_sync1;

    nCs_sync1 <= ui_in[2];
    nCs_sync2 <= nCs_sync1;
    nCs_prev <= nCs_sync2; //stores previous nCs

  end
  wire Rising_Sclk_sync = (Sclk_sync2==1'b1)&&(Sclk_sync_prev == 1'b0); //rising edge of Sclk
  wire Rising_nCs_sync = (nCs_sync2 == 1'b1)&&(nCs_prev == 1'b0); //rising edge of nCs

  reg [4:0] bit_count;
  reg [15:0] shift_reg;
  reg transaction_ready;
  reg transaction_complete;

  //TRANSACTION CAPTURE LOGIC
  //data transfer start on falling edge of nCS, sampling start on rising edge of sclk. detect negedge
  always@(posedge clk or negedge rst_n) begin
    //reset priority
    if(!rst_n) begin
      en_reg_out_7_0 <= 8'b0;
      en_reg_out_15_8 <= 8'b0;
      en_reg_pwm_7_0 <= 8'b0;
      en_reg_pwm_15_8 <= 8'b0;
      pwm_duty_cycle <= 8'b0;
      transaction_ready <= 0;
      transaction_complete <= 0;
      bit_count <= 0;
      shift_reg <= 0;

    //Does transaction start? (TRANSACTION = LOW)
    end else if (nCs_sync2 == 1'b0) begin 
      if(Rising_Sclk_sync)begin //sample COPI on every rising Sclk
        shift_reg <= {shift_reg[14:0], COPI_sync2}; //COPI shifts reg left.
        bit_count <= bit_count + 1; //count bits
      end 
    
    //CASE TRANSACTION = HIGH (STOP TRANSACTION)
    end else begin
      //TRANSACTION JUST STOPS
      if (Rising_nCs_sync)begin
        //validate the transaction: 1. 8 bit count, first bit = 1 (write), valid addr = 0 --> 0x04
        if(bit_count == 16 && //16 bits
          shift_reg[15] ==1 && //write mode
          shift_reg[14:8] >= 7'h00 && shift_reg[14:8] <= 7'h04) begin //valid address

          transaction_ready <= 1'b1;// transaction ready to be used!

        end else begin
          transaction_ready <= 1'b0; //not a valid transaction.
        end
        //reset counters
        bit_count <= 0;
        shift_reg <= 0;
      end else if (transaction_complete) begin
      //reset flag
        transaction_ready <= 0;
      end
    

  end

  always@(posedge clk or negedge rst_n)begin
    //reset priority
    if(!rst_n) begin
      en_reg_out_7_0 <= 8'b0;
      en_reg_out_15_8 <= 8'b0;
      en_reg_pwm_7_0 <= 8'b0;
      en_reg_pwm_15_8 <= 8'b0;
      pwm_duty_cycle <= 8'b0;
      transaction_complete <= 0;

    //START DOING TRANSACTION LOGIC

    //if transaction is ready and not completed
    end else if(transaction_ready&&!transaction_complete) begin
      //upload to register
      case(shift_reg[14:8])  //address
        7'h00: en_reg_out_7_0 <= shift_reg[7:0]; //enable outputs on uo_out[7:0]
        7'h01: en_reg_out_15_8 <= shift_reg[7:0]; //enable outputs on uio_out[7:0]
        7'h02: en_reg_pwm_7_0 <= shift_reg[7:0]; //enable PWM for uo_out[7:0]
        7'h03: en_reg_pwm_15_8 <= shift_reg[7:0]; //enable PWM for uio_out[7:0]
        7'h04: pwm_duty_cycle <= shift_reg[7:0];
      endcase;
      
      transaction_complete <= 1'b1;
    //what if no transaction ready and just finish transaction?
    end else if(!transaction_ready && transaction_complete) begin
      transaction_complete <= 1'b0;
    end
  end

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, ui_in[7:3], uio_in, 1'b0};

endmodule
