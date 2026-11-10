function result = run_cscan(p, mode) % EN: Shared scan procedure so the two versions do not duplicate hardware code. | 中文：两个版本共用扫描流程，避免重复硬件代码。
s = make_scan_sequence(p, mode); % EN: Build the hardware-timed motion and trigger plan first. | 中文：先生成由硬件定时执行的运动和触发计划。
assert(p.atsRate == 180e6 & p.rangeV == 4, 'This example configures 180 MS/s and +/-4 V.'); % EN: Keep numeric metadata consistent with the fixed SDK clock/range constants. | 中文：确保参数记录与下面 SDK 中固定的时钟和量程常量一致。
assert(p.recordSamples >= 256 & mod(p.recordSamples,32) == 0, 'NPT record length must be >=256 and a multiple of 32.'); % EN: Check the ATS9462 record length rule. | 中文：检查 ATS9462 的记录长度限制。
assert(p.recordSamples/p.atsRate < s.pixelSeconds, 'The NPT window must finish before the next trigger.'); % EN: Do not request overlapping NPT records. | 中文：不要求 NPT 记录相互重叠。
validateattributes(p.streamBufferSamples, {'numeric'}, {'scalar','integer','>=',256,'finite'}); % EN: A streaming buffer must have a valid whole sample count. | 中文：Streaming 缓冲区必须包含有效的整数个采样点。
assert(mod(p.streamBufferSamples,32) == 0 & p.streamBufferSamples <= 2^20, 'Use an aligned TS buffer no larger than 2^20 samples.'); % EN: Keep streaming transfers aligned and small. | 中文：保持 streaming 传输长度对齐，并限制单次传输大小。
validateattributes(p.bufferCount, {'numeric'}, {'scalar','integer','>=',2,'<=',16}); % EN: Require a small ring with at least two buffers. | 中文：要求缓冲环至少两个且不超过十六个。
validateattributes(p.timeoutMs, {'numeric'}, {'scalar','positive','finite'}); % EN: The MATLAB buffer timeout must be finite and positive. | 中文：MATLAB 的缓冲区等待超时必须有限且为正。
validateattributes(p.triggerLevelCode, {'numeric'}, {'scalar','integer','>=',0,'<=',255}); % EN: The trigger threshold is an 8-bit code. | 中文：触发阈值是 8 位编码。
samplesPerBin = round(s.pixelSeconds*p.atsRate); % EN: Convert a nominal TS bin duration to a whole sample count. | 中文：将 TS 分箱的名义时长换算为整数采样点数。
assert(abs(samplesPerBin-s.pixelSeconds*p.atsRate) < 1e-6, 'Choose a pixel duration with a whole number of ATS samples.'); % EN: Avoid silently changing the bin duration. | 中文：避免悄悄改变分箱的时间长度。
assert(2*samplesPerBin*p.nx <= 256*2^20, 'Keep a TS row below 256 MiB for this teaching example.'); % EN: Bound the one-row raw allocation even though DMA buffers are reused. | 中文：即使 DMA 缓冲区循环复用，也限制整行原始数据占用。
result = struct('settings',p,'mode',mode,'sequence',s,'previewV',nan(p.ny,p.nx),'rowsDone',0,'complete',false,'hardwareRun',false,'folder',''); % EN: Keep settings, planned timing, progress, and preview together. | 中文：将参数、计划时序、进度和预览结果放在一起。
if p.showPlot % EN: Plot only if requested. | 中文：根据设置决定是否画图。
    figure('Name', 'Planned timing / 计划时序'); % EN: Open a timing figure. | 中文：打开时序图窗口。
    plot((0:size(s.forward,1)-1)/p.niRate, double(s.forward(:,[1 5]))); % EN: Plot the planned X STEP and acquisition trigger against NI time. | 中文：按 NI 时间画出计划的 X STEP 和采集触发。
    legend('X STEP','Acquisition trigger'); xlabel('NI time (s)'); % EN: Identify the two signals and their time unit. | 中文：标注两路信号和时间单位。
end % EN: Finish plotting the plan. | 中文：结束计划时序绘图。
if ~p.runHardware % EN: Stop here in the default offline mode. | 中文：默认离线模式到这里就停止。
    disp('Plan only: no hardware used and no measured image produced.'); % EN: Make clear that planned timing is not experimental data. | 中文：明确说明计划时序不是实验数据。
    return % EN: Return the plan without opening NI or ATS. | 中文：不打开 NI 或 ATS，直接返回计划。
end % EN: Everything below this point uses real laboratory hardware. | 中文：从这里往下才会使用实验室真实硬件。
assert(ispc, 'Run hardware only on the laboratory Windows PC.'); % EN: The Mac can study and check the code, but has no attached cards. | 中文：Mac 可学习和检查代码，但没有连接这些板卡。
assert(isfolder(p.sdkFolder), 'Set p.sdkFolder to the installed ATS SDK Include directory.'); % EN: Check the SDK path before starting any movement. | 中文：在任何运动开始前检查 SDK 路径。
addpath(p.sdkFolder); % EN: Make the vendor MATLAB functions available. | 中文：让 MATLAB 能找到厂商提供的函数。
AlazarDefs; % EN: Load the vendor names for hardware constants. | 中文：载入厂商定义的硬件常量名称。
alazarLoadLibrary(); % EN: Load the ATS Windows driver library. | 中文：载入 ATS 的 Windows 驱动库。
board = AlazarGetBoardBySystemID(int32(1), int32(1)); % EN: Select board 1 in system 1. | 中文：选择系统 1 中的第 1 块板卡。
assert(strcmp(AlazarGetBoardKind(board), 'ATS9462'), 'This example targets ATS9462.'); % EN: Check that the connected board matches this example; the SDK returns the board kind as text, so compare with strcmp. | 中文：检查连接的板卡型号与示例一致；SDK 以字符形式返回板卡型号，因此用 strcmp 比较。
[memorySamples, bits] = AlazarGetChannelInfo(board); % EN: Read the onboard memory capacity and ADC resolution. | 中文：读取板载存储容量和 ADC 位数。
assert(double(bits) == 16 & double(memorySamples) > 0, 'This version requires the 16-bit ATS9462 with onboard memory.'); % EN: Reject the FIFO-only variant because its DMA flags differ. | 中文：FIFO-only 版本的 DMA 标志不同，因此本版不接受它。
AlazarSetCaptureClock(board, INTERNAL_CLOCK, SAMPLE_RATE_180MSPS, CLOCK_EDGE_RISING, 0); % EN: Set ATS to its internal 180 MS/s sampling clock. | 中文：将 ATS 设置为内部 180 MS/s 采样时钟。
AlazarInputControlEx(board, CHANNEL_A, DC_COUPLING, INPUT_RANGE_PM_4_V, IMPEDANCE_50_OHM); % EN: Configure CH A for DC coupling, +/-4 V, and 50 ohms. | 中文：设置 CH A 为直流耦合、正负 4 伏和 50 欧姆输入。
AlazarSetBWLimit(board, CHANNEL_A, 0); % EN: Disable the optional bandwidth limit, as in the existing program. | 中文：与现有程序一样，关闭可选带宽限制。
AlazarSetExternalTrigger(board, DC_COUPLING, ETR_5V); % EN: Configure the external trigger input range and coupling. | 中文：设置外触发输入的量程和耦合方式。
AlazarSetTriggerOperation(board, TRIG_ENGINE_OP_J, TRIG_ENGINE_J, TRIG_EXTERNAL, TRIGGER_SLOPE_POSITIVE, p.triggerLevelCode, TRIG_ENGINE_K, TRIG_DISABLE, TRIGGER_SLOPE_POSITIVE, 128); % EN: Use rising external triggers on engine J and disable engine K. | 中文：使用引擎 J 检测外部上升沿触发，并关闭引擎 K。
AlazarSetTriggerDelay(board, 0); % EN: Request zero programmed delay after the trigger. | 中文：将触发后的可编程延迟设为零。
AlazarSetTriggerTimeOut(board, 0); % EN: Disable automatic timeout triggers: no valid edge means no triggered acquisition. | 中文：关闭自动超时触发：没有有效沿就不开始触发采集。
AlazarConfigureAuxIO(board, AUX_OUT_SERIAL_DATA, 0); % EN: Hold AUX low; this version does not use AUX pulses or a counter for mapping. | 中文：将 AUX 保持低电平；本版不使用 AUX 脉冲或计数器做位置映射。
dq = daq("ni"); % EN: Create one NI acquisition/output object. | 中文：创建一个 NI 输入输出对象。
niGuard = onCleanup(@() stop(dq)); % EN: Stop NI if this function exits normally or with an error. | 中文：此函数正常结束或报错时都停止 NI。
ai = addinput(dq, p.device, "ai1", "Voltage"); % EN: Add the AI channel used to provide clocked digital-output timing. | 中文：添加 AI 通道，为定时数字输出提供时钟。
ai.TerminalConfig = "Differential"; % EN: Match the differential input setup in the existing program. | 中文：沿用现有程序中的差分输入设置。
lines = ["port0/line0","port0/line1","port0/line2","port0/line3","port0/line6"]; % EN: Map the five table columns to X STEP/DIR, Y STEP/DIR, and acquisition trigger. | 中文：将五列映射到 X STEP/DIR、Y STEP/DIR 和采集触发。
for k = 1:numel(lines) % EN: Add the output lines in exactly the same order as the table. | 中文：按时序表的列顺序添加输出通道。
    addoutput(dq, p.device, lines(k), "Digital"); % EN: Add one NI digital output. | 中文：添加一个 NI 数字输出。
end % EN: Finish adding the five output lines; P0.7 is not used. | 中文：五个输出通道添加完成；不使用 P0.7。
dq.Rate = p.niRate; % EN: Set the shared NI scan/output sample rate. | 中文：设置 NI 共用的输入输出采样时钟频率。
assert(abs(dq.Rate-p.niRate) < 1e-6, 'NI changed the requested rate; recompute timing first.'); % EN: Reject unexpected rate coercion rather than mislabel the timing. | 中文：如果 NI 改变请求频率就报错，避免使用错误的时间标签。
result.folder = fullfile(p.outputRoot, char(mode+"_"+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS')))); % EN: Choose a time-stamped folder for this scan. | 中文：为此次扫描创建带时间戳的目录名。
assert(~isfolder(result.folder), 'Output folder already exists.'); % EN: Do not overwrite an existing run. | 中文：不覆盖已有的运行数据。
mkdir(result.folder); % EN: Create the output folder before motion starts. | 中文：在运动开始前创建输出目录。
save(fullfile(result.folder,'plan.mat'), 'p', 's', 'mode'); % EN: Save settings and commanded timing even if a later row fails. | 中文：先保存参数和命令时序，后续某行失败时仍可查到计划。
result.hardwareRun = true; % EN: Mark that this invocation entered the hardware path. | 中文：标记本次调用已经进入硬件运行路径。
for row = 1:p.ny % EN: Repeat one forward acquisition for every Y row. | 中文：每个 Y 行重复一次正向采集。
    raw = acquire_row(board, dq, p, s, mode); % EN: Prepare DMA, arm ATS, start NI, and copy this row into MATLAB memory. | 中文：准备 DMA、启动 ATS 等待、启动 NI，并把本行数据复制到 MATLAB。
    wait_for_ni(dq, size(s.forward,1)/p.niRate); % EN: Let the whole commanded X move finish before changing direction. | 中文：等整段 X 命令运动结束后再改变方向。
    preview = cscan_preview(raw, p, mode); % EN: Calculate one basic amplitude value per X bin. | 中文：为每个 X 分箱计算一个简单幅度值。
    yUm = s.yUm(row); % EN: Record the commanded Y coordinate of this row. | 中文：记录这一行的 Y 命令坐标。
    save(fullfile(result.folder,sprintf('row_%03d.mat',row)), 'raw','preview','yUm','row','-v7.3'); % EN: Save the raw row before moving to the next Y position. | 中文：在移动到下一个 Y 位置前保存本行原始数据。
    result.previewV(row,:) = preview; % EN: Put this row into the 2-D preview array. | 中文：把本行预览放入二维数组。
    result.rowsDone = row; % EN: Record how many rows were acquired and saved. | 中文：记录已经采集并保存的行数。
    readwrite(dq, double(s.back), "OutputFormat", "Matrix"); % EN: Return X with triggers low; blocking is acceptable because ATS has stopped. | 中文：关闭触发并让 X 回程；ATS 已停止，所以这里可以阻塞等待。
    if row < p.ny % EN: Do not step Y after the final row. | 中文：最后一行后不再前进 Y。
        readwrite(dq, double(s.yNext), "OutputFormat", "Matrix"); % EN: Move Y to the next row while acquisition is stopped. | 中文：在采集停止时把 Y 移动到下一行。
    end % EN: Finish the between-row Y move. | 中文：结束行间 Y 移动。
end % EN: Finish acquiring every row. | 中文：完成所有行的采集。
readwrite(dq, double(s.yHome), "OutputFormat", "Matrix"); % EN: Reverse all commanded Y steps; this is not limit-switch homing. | 中文：反向走完全部 Y 命令步数；这不是通过限位开关归零。
result.complete = true; % EN: Mark success only after acquisition and normal commanded returns finish. | 中文：只有采集及正常命令回程全部完成后才标记成功。
save(fullfile(result.folder,'summary.mat'), 'result'); % EN: Save the preview and completion status. | 中文：保存预览图数据和完成状态。
if p.showPlot % EN: Show the measured preview if requested. | 中文：根据设置决定是否显示实测预览。
    figure('Name','Amplitude preview / 幅度预览'); % EN: Open a separate figure for the preview. | 中文：为预览图打开单独窗口。
    imagesc(s.xStartUm, s.yUm, result.previewV); axis xy; colorbar; % EN: Display volts against nominal commanded coordinates. | 中文：按名义命令坐标显示以伏特为单位的结果。
    xlabel('Nominal X bin start (um)'); ylabel('Commanded Y (um)'); % EN: Label the axes without claiming measured spatial accuracy. | 中文：标注坐标，但不把命令坐标说成已测得的精确位置。
    title(mode+": voltage-range preview, not depth reconstruction"); % EN: State explicitly what the displayed quantity means. | 中文：明确说明显示的是电压范围预览，不是深度重建。
end % EN: Finish preview display. | 中文：结束预览绘图。
end % EN: Finish the shared C-scan procedure. | 中文：结束共用 C-scan 流程。
function raw = acquire_row(board, dq, p, s, mode) % EN: Acquire exactly one row using mode-specific DMA settings. | 中文：按所选模式的 DMA 设置采集一行。
AlazarDefs; % EN: Make SDK constants available inside this local function. | 中文：在此局部函数中载入 SDK 常量。
if mode == "NPT" % EN: Choose the short-record acquisition layout. | 中文：选择短记录采集布局。
    samples = p.recordSamples; % EN: Number of samples in each NPT record. | 中文：每条 NPT 记录的采样点数。
    records = gcd(p.nx,10); % EN: Group up to ten records per buffer while dividing nx exactly. | 中文：每个缓冲区最多放十条记录，并保证正好整除 nx。
    acquisitionRecords = p.nx; % EN: Request exactly one triggered record per planned X position. | 中文：每个计划 X 位置请求一条触发记录。
    wanted = samples*p.nx; % EN: Total number of ADC samples to retain in this row. | 中文：本行需要保留的 ADC 总采样点数。
    flags = bitor(ADMA_EXTERNAL_STARTCAPTURE, ADMA_NPT); % EN: NPT waits for triggers after the explicit StartCapture call. | 中文：NPT 在显式调用 StartCapture 后等待触发。
    AlazarSetRecordSize(board, 0, samples); % EN: Use zero pre-trigger samples and the chosen post-trigger length. | 中文：使用零个预触发点和指定数量的触发后采样点。
else % EN: Choose the per-row Triggered Streaming layout. | 中文：选择每行触发一次的连续采样布局。
    samples = p.streamBufferSamples; % EN: Transfer this many samples in each streaming buffer. | 中文：每个 streaming 缓冲区传输这么多采样点。
    records = 1; % EN: SDK streaming modes require one record per buffer. | 中文：SDK 的 streaming 模式要求每缓冲区记录数设为一。
    acquisitionRecords = hex2dec('7FFFFFFF'); % EN: SDK streaming convention: keep going until AbortAsyncRead. | 中文：SDK 的 streaming 约定：持续采集，直到调用 AbortAsyncRead。
    wanted = round(s.pixelSeconds*p.atsRate)*p.nx; % EN: Retain the requested duration by counting samples, not by a software stopwatch. | 中文：按采样点数保留指定时间段，不依赖软件秒表决定数据长度。
    flags = bitor(ADMA_EXTERNAL_STARTCAPTURE, ADMA_TRIGGERED_STREAMING); % EN: Wait for the first hardware trigger, then sample without gaps. | 中文：等待第一个硬件触发，然后不间断采样。
end % EN: Finish selecting NPT or TS parameters. | 中文：结束 NPT 或 TS 参数选择。
perBuffer = samples*records; % EN: Total 16-bit samples transferred by one buffer. | 中文：一个缓冲区传输的 16 位采样点总数。
bytes = 2*perBuffer; % EN: A 16-bit sample occupies two bytes. | 中文：一个 16 位采样点占两个字节。
nBuffers = ceil(wanted/perBuffer); % EN: Read enough complete buffers to cover the desired row. | 中文：读取足够多的完整缓冲区，以覆盖需要的整行数据。
ringSize = min(p.bufferCount,nBuffers); % EN: Allocate only as many ring buffers as this row can use. | 中文：只分配本行实际能用到的缓冲区数量。
buffers = cell(1,ringSize); % EN: Keep the DMA memory pointers in a cell array. | 中文：用 cell 数组保存 DMA 内存指针。
raw = zeros(wanted,1,'uint16'); % EN: Allocate one row of raw unsigned ADC codes. | 中文：为一行无符号 ADC 原始编码分配内存。
try % EN: Also clean up a partially allocated ring if memory allocation fails. | 中文：内存分配中途失败时，也要清理已经分配的部分。
for k = 1:ringSize % EN: Allocate the small reusable ring. | 中文：分配小型可循环复用缓冲环。
    buffers{k} = AlazarAllocBuffer(board, bytes); % EN: Ask the SDK for DMA-compatible memory. | 中文：向 SDK 申请可用于 DMA 的内存。
end % EN: Finish allocation before starting acquisition. | 中文：在开始采集前完成内存分配。
catch err % EN: Handle a failure before the normal cleanup guard exists. | 中文：处理正常清理对象建立之前发生的分配失败。
    release_buffers(board, buffers); % EN: Free any DMA buffers already allocated. | 中文：释放此前已经分配的 DMA 缓冲区。
    rethrow(err); % EN: Preserve and report the original allocation error. | 中文：保留并报告原来的分配错误。
end % EN: Finish the allocation error handler. | 中文：结束分配错误处理。
rowGuard = onCleanup(@() release_buffers(board, buffers)); % EN: Capture the completed pointer list for cleanup on return or error. | 中文：保存完整指针列表，正常返回或报错时都用它清理。
AlazarBeforeAsyncRead(board, CHANNEL_A, 0, samples, records, acquisitionRecords, flags); % EN: Describe the acquisition and transfer layout to the board. | 中文：向板卡指定采集方式和数据传输布局。
for k = 1:ringSize % EN: Give every initial buffer to the board. | 中文：将所有初始缓冲区交给板卡。
    AlazarPostAsyncBuffer(board, buffers{k}, bytes); % EN: Queue one empty buffer for incoming ADC data. | 中文：排队提交一个空缓冲区，等待 ADC 数据填入。
end % EN: The board now has empty buffers available. | 中文：此时板卡已经有可用的空缓冲区。
preload(dq, double(s.forward)); % EN: Queue NI motion and trigger data without starting it. | 中文：预载 NI 运动和触发时序，但先不启动。
AlazarStartCapture(board); % EN: Arm ATS first; it waits for the controlled external trigger. | 中文：先启动 ATS 等待；它会等待受控的外部触发。
start(dq); % EN: Start the NI hardware-timed sequence after ATS is armed. | 中文：ATS 准备等待后，再启动 NI 硬件定时时序。
for b = 1:nBuffers % EN: Copy completed buffers until the desired row is covered. | 中文：逐个复制完成的缓冲区，直到覆盖需要的整行数据。
    k = mod(b-1,ringSize)+1; % EN: Cycle through buffer indices 1, 2, ..., ringSize. | 中文：循环选择第 1、2、直到 ringSize 个缓冲区。
    AlazarWaitAsyncBufferComplete(board, buffers{k}, p.timeoutMs); % EN: Wait until this buffer is full; timeout/overflow raises an error. | 中文：等待此缓冲区填满；超时或溢出会报错。
    setdatatype(buffers{k}, 'uint16Ptr', 1, perBuffer); % EN: Interpret the DMA bytes as 16-bit unsigned samples. | 中文：将 DMA 字节解释为 16 位无符号采样点。
    first = (b-1)*perBuffer+1; % EN: Find where this buffer belongs in the row array. | 中文：计算此缓冲区在整行数组中的起始位置。
    count = min(perBuffer,wanted-first+1); % EN: Trim the final TS buffer to the requested valid sample count. | 中文：将最后一个 TS 缓冲区裁剪到所需的有效采样点数。
    data = buffers{k}.Value; % EN: Copy the completed DMA buffer into a MATLAB value. | 中文：将完成的 DMA 缓冲区复制为 MATLAB 数据。
    raw(first:first+count-1) = data(1:count); % EN: Append the valid part of this buffer in chronological order. | 中文：按时间顺序追加此缓冲区的有效部分。
    if b+ringSize <= nBuffers % EN: Reuse this buffer only when a later transfer will need it. | 中文：只有后续传输还需要它时才再次提交。
        AlazarPostAsyncBuffer(board, buffers{k}, bytes); % EN: Return the copied buffer to the DMA queue. | 中文：将已经复制完的缓冲区重新交回 DMA 队列。
    end % EN: Finish deciding whether to reuse this buffer. | 中文：结束是否复用缓冲区的判断。
end % EN: All requested samples have now been copied. | 中文：所有需要的采样点已经复制完成。
AlazarAbortAsyncRead(board); % EN: Stop ATS before processing data or starting the return motion. | 中文：在处理数据或开始回程前停止 ATS。
clear rowGuard % EN: Abort again harmlessly, then release the allocated DMA memory now. | 中文：再次中止并立即释放已分配的 DMA 内存。
end % EN: Finish this row acquisition function. | 中文：结束本行采集函数。
function release_buffers(board, buffers) % EN: Clean up the explicit pointer list passed by the caller. | 中文：清理由调用者明确传入的缓冲区指针列表。
        try % EN: Abort must succeed before any DMA buffer is freed. | 中文：释放任何 DMA 缓冲区之前必须成功中止采集。
            AlazarAbortAsyncRead(board); % EN: Stop acquisition and release the board's claim on queued buffers. | 中文：停止采集，解除板卡对已提交缓冲区的使用。
        catch err % EN: Handle an abort failure without hiding the original error. | 中文：处理中止失败，同时避免掩盖原始错误。
            warning('SimpleCscan:Abort','DMA abort failed; buffers retained: %s',err.message); % EN: Keep memory allocated when the board might still be using it. | 中文：板卡可能仍在使用这些内存时，不释放它们。
            return % EN: Do not free possibly active DMA memory. | 中文：不释放可能仍在使用的 DMA 内存。
        end % EN: A successful abort makes freeing buffers appropriate. | 中文：成功中止后才能释放缓冲区。
        for j = 1:numel(buffers) % EN: Visit every pointer that may have been allocated. | 中文：检查每个可能已分配的指针。
            if ~isempty(buffers{j}) % EN: Skip cells whose allocation never completed. | 中文：跳过尚未成功分配的空单元。
                AlazarFreeBuffer(board, buffers{j}); % EN: Return this DMA allocation to the SDK. | 中文：通过 SDK 释放这一块 DMA 内存。
            end % EN: Finish checking this allocation. | 中文：结束此内存块的判断。
        end % EN: Finish freeing the buffer ring. | 中文：缓冲环释放完毕。
end % EN: Finish the DMA cleanup function. | 中文：结束 DMA 清理函数。
function wait_for_ni(dq, durationS) % EN: Wait for the remaining finite NI motion without changing the ATS sample count. | 中文：等待剩余的有限 NI 运动；不改变 ATS 保留的采样点数。
timer = tic; % EN: Start a watchdog for a stuck NI operation, not an acquisition timing reference. | 中文：启动 NI 卡住时的监测秒表；它不是采集时间基准。
while dq.Running % EN: Continue waiting while NI is still outputting the sequence. | 中文：NI 仍在输出时序时继续等待。
    assert(toc(timer) < durationS+5, 'NI did not finish its finite sequence.'); % EN: Report a stuck run rather than wait forever. | 中文：如果有限时序一直未结束就报错，不无限等待。
    pause(0.005); % EN: Yield MATLAB briefly while the NI hardware keeps working. | 中文：MATLAB 短暂让出执行时间，NI 硬件仍继续工作。
end % EN: NI has completed its finite output. | 中文：NI 已完成有限长度的输出。
read(dq, "all", "OutputFormat", "Matrix"); % EN: Drain the unused AI samples so they do not accumulate across rows. | 中文：读掉不用的 AI 样本，防止它们逐行积累。
end % EN: Finish the NI waiting helper. | 中文：结束 NI 等待辅助函数。
