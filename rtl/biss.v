//此模块包括整个程序，并且调节
module biss
(
    input       clk         ,   //输入50M 时钟
    input       rx          ,   // 由编码器输入的信号 SL
    input       rst         ,   // 复位
    input       verify_rx   ,   // fpga 内部确认接收编码器的数据 标志位

    output  reg syn_biss_clk        // 输入给编码器的同步时钟信号
);


reg [35:0]      txdata          ; // 接收到的数据存储
reg [2:0]       read_data_state ; // 读取编码器数据时，所使用状态机的状态变换
localparam  rest_state          = 0 ; //空闲状态，编码器没有输出高电平
localparam  encoder_ready_ok    = 1 ; // 编码器数据准备好，编码器高电平输出，输出 1M时钟
localparam  syn_clk             = 2 ; // 编码器反馈一个下降沿，此时重置syn_biss_clk时钟从零计时，与编码器时钟同步
localparam  rxdata_state        = 3 ; // 读取数据状态，数据读取完成后存储数据，并返回到第一个状态

//编码器准备好后，捕捉编码器输出的下降沿
reg         rx_d0   ;   // 对rx (SL) 延迟一个时钟
reg         rx_d1   ;   // 对rx_d0延迟一个时钟，对rx 延迟2个时钟
reg         rx_negedge; // 下降沿

// 检测编码器输入start位的上升沿
reg         rx_d2   ;   // 对rx延迟 1 个时钟，
reg         rx_d3   ;   // 对rx_d2 延迟 1 个时钟，对 rx 延迟 2 个时钟
reg         rx_posedge; // 上升沿

// 在读取数据时，将初始化上升沿与下降沿信号
always @(posedge clk or negedge rst ) // 时钟的上升沿 和 复位 的下降沿
begin
    if (rst == 1'b0)
        begin
            rx_d0 <= 1'b0;      //对rx延迟 1 个时钟
            rx_d1 <= 1'b0;      //对rx_d0 延迟 1 个时钟
            rx_negedge <= 1'b0; // 下降沿
            rx_d2 <= 1'b0 ;     //对rx延迟 1 个时钟
            rx_d3 <= 1'b0 ;     // 对 rx_d2 延迟 1 个时钟
            rx_posedge <= 1'b0; // 上升沿
        end
    else if (read_data_state == rxdata_state)  // 状态3 ,读取数据完成，rx归零
        begin
            rx_d0 <= 1'b0;      //对rx延迟 1 个时钟
            rx_d1 <= 1'b0;      //对rx_d0 延迟 1 个时钟
            rx_negedge <= 1'b0; // 下降沿
            rx_d2 <= 1'b0 ;     //对rx延迟 1 个时钟
            rx_d3 <= 1'b0 ;     // 对 rx_d2 延迟 1 个时钟
            rx_posedge <= 1'b0; // 上升沿
        end
    // 检测编码器下降沿， 编码器对 FPGA 发送过来的信号的应答，进入 syn_clk 状态
    else if (read_data_state == encoder_ready_ok) //状态1 ，编码求数据准备好，编码器高电平输出 1M 时钟
        begin
            rx_d0   <= rx ;  // 时序逻辑，rx_d0 延迟rx 1 个时钟周期
            rx_d1   <= rx_d0    ; // rx_d1 延迟 rx_d0 1 个时钟周期
            rx_negedge <= rx_d1 && ~rx_d0; // 
            rx_posedge <= 1'b0;
        end

    // 检测到编码器上升沿，即编码器发送过来的start位
    else if (read_data_state == syn_clk) // 状态2 ，编码求反馈一个下降沿，此时重置syn_biss_clk
        begin
            rx_d2   <= rx ; //rx_d2 延迟 rx 1 个时钟周期
            rx_d3   <= rx_d2; // rx_d3 延迟rx_d2 1 个时钟周期
            rx_posedge <= ~rx_d3 && rx_d2   ;
            rx_negedge  <= 1'b0;
        end
end

reg [7:0]   ready_ok_cont   ;
reg [7:0]   syn_clk_cont    ;
reg [7:0]   clk_cnt         ;   //计数，50M时钟下 50 个上升沿，对应1M时钟下的biss_clk 上升沿

//计数状态
always @ (posedge clk or negedge rst)
begin
    if (rst == 1'b0)
    begin
        ready_ok_cont <= 8'd0;
        syn_clk_cont  <= 8'd0;
        clk_cnt       <= 8'd0;
    end

    // 空闲状态 rest_state = 0
    else if (read_data_state == rest_state)
        begin
            syn_biss_clk    <= 1'b1;    // 输出时钟(MA) 输出 高电平
            clk_cnt         <= 8'd0;
            ready_ok_cont   <= 8'd0;
            syn_clk_cont    <= 8'd0;
        end

    // 编码器准备好 encoder_ready_ok=  1
    //  输出syn_biss_clk
    else if (read_data_state == encoder_ready_ok)
    begin   

        if (ready_ok_cont <= 8'd24) // 起到分频器的作用， 50一个周期
        begin
            syn_biss_clk    <= 1'b0; // 输出 0 
            ready_ok_cont   <= ready_ok_cont + 8'd1;
        end

        else if (ready_ok_cont < 8'd49)
        begin
            syn_biss_clk    <= 1'b1; //输出1 
            ready_ok_cont   <= ready_ok_cont + 8'd1;
        end

        else if (ready_ok_cont == 8'd49)    
        begin
            syn_biss_clk    <= 1'b1;
            ready_ok_cont   <= 8'd0;
        end
    end
    
    //syn_clk   状态2
    else if (read_data_state == syn_clk)
    begin

        if (rx_posedge == 1'b1) // 检测到上升沿，说明进入start位，需要将 syn_biss_clk (MA)置为0        
        begin
            syn_biss_clk    <= 1'b0;
        end

        else if (syn_clk_cont <= 8'd24)
        begin
             syn_biss_clk   <= 1'b1;
             syn_clk_cont   <= syn_clk_cont + 1'd1;
        end

        else if (syn_clk_cont < 8'd49)
        begin
            syn_biss_clk    <= 1'b0;
            syn_clk_cont    <= syn_clk_cont + 8'd1;
        end

        else if (syn_clk_cont == 8'd49)
        begin
            syn_biss_clk    <= 1'b0;
            syn_clk_cont    <= 8'd0;
        end
    end

    // 在 rxdata_state = 3 ，状态3，对应 1M时钟输出
    else if (read_data_state == rxdata_state) // 主程序发送可以接收编码器 确认
    begin

        if (clk_cnt < 8'd24) // 50 个上升沿 ，计数 1M 时钟的1 个下降沿
        begin
            clk_cnt <= clk_cnt + 8'd1;
            syn_biss_clk    <= 1'b1;
        end        

        else if (clk_cnt < 8'd49)
        begin
            clk_cnt <= clk_cnt + 8'd1;
            syn_biss_clk    <= 1'b0;
        end

        else if (clk_cnt == 8'd49)
        begin
            clk_cnt <= clk_cnt + 8'd1;
            //syn_biss_clk    <= 1'b0;
            syn_biss_clk    <= ~syn_biss_clk; // 反转 syn_biss_clk
        end
    end

end


// 总控程序
reg [5:0] cont_data ; // 对编码器发过来的数据进行计数
reg con_digital49   ; //在syn_biss_clk == 1'b1 时，与con_digital == 0 时，才可以给txdata赋值


always @ (posedge clk or negedge rst)
begin
    if (rst == 1'b0)
    begin
        read_data_state <= rest_state   ; // 初始状态是 空闲状态 0
        txdata          <= 36'b0;
        cont_data       <= 6'd0;
        con_digital49   <= 1'b0;
    end

    else if (verify_rx == 1'b1)
    begin
        case (read_data_state)

        rest_state: // 空闲状态，编码器低电平输出，(SL=0),syn_biss_clk高电平输出(MA=1)
                    // 检测到编码器高电平输出，转到下一个状态
        begin
            if (rx == 1'b1)
            begin
                read_data_state <= encoder_ready_ok;
            end
        end

        encoder_ready_ok: //编码器准备好，fpga输出1M时钟给编码器
                            // 检测到编码器下降沿 ，并转到下一状态
        begin
            txdata  <= 36'd0;
            cont_data   <= 6'd0;
            con_digital49   <=1'b0;
            if (rx_negedge == 1'b1) //检测到下降沿
            begin
                read_data_state <= syn_clk;
            end
        end

        syn_clk:    // 此时同步时钟，当检测到上升沿时候，编码器start位，转下一个状态位
        begin
            if (rx_posedge == 1'b1)
            begin
                read_data_state <= rxdata_state;
            end
        end

        rxdata_state: // 读取输出状态，数据读取完成后存储数据，并返回到第一个状态,从start读取
        begin
            if ( (syn_biss_clk == 1'b1) && (cont_data < 6'd36) && (con_digital49 == 1'b0))
             begin
                // 接收数据
                txdata[cont_data] <= rx ;
                cont_data <= cont_data + 6'd1;
                con_digital49 <= con_digital49 + 1'b1;
             end

            else if ((syn_biss_clk == 1'b1) && cont_data == 6'd36 && con_digital49 == 1'b0)
                begin
                    read_data_state <= rest_state; // 读完36个数据后，返回到空闲状态，将sys_biss_clk 置为1
                    con_digital49 <= con_digital49 + 1'b1;
                end

            else 
                begin
                    if (syn_biss_clk == 1'b0)
                        begin
                            con_digital49 <= 1'b0;
                        end
                end
        end

        default : read_data_state <= rest_state ; // 遇到意外，回到空闲状态
        endcase
    end

end

// 奇偶校验位，除数为 1000011，通过“模2除法” 实验 CRC
// 运用verilog 语言对接收的数据和除数 取异或或移位操作，最后等于 0 ，即接收到的是正确的数据
reg         right_txdata;   // 当接收的数据正确时，right_txdata = 1
reg [6:0]   crc_divisor ;  // 校验运用的多形式为 X^6+x^1+x^0，对应的除数为 1000011
reg [6:0]   waiting_xor ;   // 待取异或的数值，实时更新，取完余数，然后用txdata补充
reg         yes_move    ;   // 确定了移位操作
reg         crc_ok      ;   
reg [7:0]   cont_txdata ;   // 计数

always @ (posedge clk or negedge rst)
begin
    if (rst == 1'b0)// 初始化
    begin
        right_txdata <= 1'b0;
        crc_divisor <=  7'b1000011; // 被除数
        waiting_xor <=  7'b0;       //除数
        cont_txdata <=  7'd0;       // 给txdata 计数
        yes_move    <=  1'b0;       // 确定移位时，置为1
        crc_ok      <=  1'b0;       //完成校验，跳出循环
    end

    else if (read_data_state == syn_clk) // 在同步时钟状态时，将right_txdata 置为0
    begin
        right_txdata    <= 1'b0;    
        crc_divisor     <= 7'b1000011;  //被除数
        waiting_xor     <= 7'b0;        //除数
        cont_txdata     <= 7'd0;    //给txdata 计数
        yes_move        <= 1'b0;    //确定移位时，置为1
        crc_ok          <= 1'b0;    
    end

    else if (cont_data == 6'd36 && crc_ok == 1'b0 ) // 当读取完36位时，进行crc校验
    begin
        // 初始化 7位数
        if (cont_txdata == 7'd0)
        begin
            waiting_xor <= {txdata[2],txdata[3],txdata[4],txdata[5],txdata[6],txdata[7],txdata[8]};
        cont_txdata <= cont_txdata  + 7'd9;
        end

        // 如果移位了，把waiting_xor 最后移位，用txdata的候补位补齐
        else if (yes_move == 1'b1)
        begin
            yes_move <= 1'b0;

            if (cont_txdata <= 7'd36)
            begin
                waiting_xor[0] <= txdata[cont_txdata - 7'd1]; // 移位后需要把最低位赋值，
            end
        end

        // 判断高位是否为0 ，如果为0 移位操作，有几个0 ，移动几位
        else if (waiting_xor < 7'b1000000 && cont_txdata <= 7'd35)
        begin
            waiting_xor <= waiting_xor << 1 ;//移动 1 位
            cont_txdata <= cont_txdata + 7'd1 ; //移位之后，需要用txdata 对waiting_xor 补进
            yes_move    <= 1'b1;
        end


        //如果waiting_xor 的最高位为 1 ，进行 异或操作
        else if (waiting_xor > 7'b1000000 || cont_txdata == 7'd36)
        begin
            waiting_xor <= waiting_xor ^ crc_divisor ; // 取异或操作
            // 如果已经 异或完 34 位数后，进行最后的判断
            if (cont_txdata == 7'd36)
                begin
                    crc_ok <= 1'b1; // 完成校验后，退出该位置
                end
        end
    end
    
    // 当对传入的数据奇偶校验完后，判断奇偶校验位最后的结果waiting_xor 是否为0
    // 如果结果为 0 ，则接收数据没有错误，否则数据错误，不与存储
    else if (crc_ok == 1'b1)
        begin
            if (waiting_xor == 7'b0)
            begin
                right_txdata <= 1'b1;
            end
            else 
            begin
                right_txdata <= 1'b0;
            end
        end

end

//  如果读取的数据正确 ，则将txdata 的数据位，放到con_right_data
reg [5:0] con_right_data    ;
always @(posedge clk or negedge rst)
begin
    if (rst == 1'b0)
        begin
            right_txdata <= 1'b0;
            con_right_data <= 26'b0;
        end
    else if (right_txdata == 1'b1)
        begin
            con_right_data <= txdata[27:2];
        end
end

endmodule