function values = cscan_preview(raw, p, mode) % EN: Make a basic voltage-range preview; this is not depth reconstruction. | 中文：生成简单的电压范围预览；这里没有做深度重建。
if mode == "NPT" % EN: In NPT, every column is one triggered short record. | 中文：NPT 中，每列是一条触发后的短记录。
    block = reshape(raw, p.recordSamples, p.nx); % EN: Put samples down the rows and X records across the columns. | 中文：每列沿纵向放采样点，横向排列不同 X 记录。
else % EN: In TS, divide continuous time into nominal X bins. | 中文：TS 中，将连续时间划分为名义 X 分箱。
    block = reshape(raw, [], p.nx); % EN: Equal-duration bins are not individual laser pulses. | 中文：等时间分箱不等于逐个激光脉冲。
end % EN: Finish choosing the data layout. | 中文：结束数据排列方式选择。
span = double(max(block,[],1)) - double(min(block,[],1)); % EN: Find the largest minus smallest ADC code in each column. | 中文：计算每列最大 ADC 编码减最小 ADC 编码。
values = span * (2*p.rangeV/65535); % EN: Convert the code difference to volts for a 16-bit unsigned ADC. | 中文：对 16 位无符号 ADC，将编码差换算为伏特。
end % EN: Return one preview value per X bin. | 中文：每个 X 分箱返回一个预览值。
