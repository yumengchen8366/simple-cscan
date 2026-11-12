function result = pam_scan(mode, p)

if nargin < 1, mode = "NPT"; end
if nargin < 2, p = pam_settings(); end
mode = upper(string(mode));
s = pam_sequence(p,mode);
result = struct('mode',mode,'settings',p,'sequence',s,'folder','', ...
    'rowsDone',0,'complete',false,'hardwareRun',false,'previewV',[]);
fprintf('X %.6g mm/s; Y %.6g mm/s; pixel %.6g us; row %.6g s.\n', ...
    s.xSpeedMmS,s.ySpeedMmS,1e6*s.pixelSeconds,s.rowSeconds);
fprintf('X travel %.6g mm; %d rows; NI output time %.6g s (excludes software/I/O).\n', ...
    s.xSteps*p.stepUm/1000,p.ny,s.motionSeconds);
fprintf('%s: raw row %.3f MiB; DMA ring %.3f MiB; %d transfers/row; total raw %.3f GiB.\n', ...
    mode,s.rowBytes/2^20,s.dmaBytes/2^20,s.bufferTransfers,s.totalRawBytes/2^30);
if p.showPlot
    n = min(size(s.forward,1),3*s.pixelTicks+1);
    figure('Name','Planned NI timing');
    stairs((0:n-1)/p.niRate*1e6,double(s.forward(1:n,[1 5])));
    xlabel('NI time (us)'); legend('X STEP','ATS trigger'); grid on;
end
if ~p.runHardware, disp('Plan only: no hardware opened.'); return; end

assert(ispc, 'Hardware runs require the laboratory Windows PC.');
board = [];
if mode ~= "MOTOR", board = open_ats(p); end
dq = daq("ni");
dq.UserData = [];
niGuard = onCleanup(@() close_ni(dq));
ai = addinput(dq,p.device,"ai1","Voltage");
ai.TerminalConfig = "Differential";
for line = [0 1 2 3 6]
    addoutput(dq,p.device,"port0/line"+string(line),"Digital");
end
dq.Rate = p.niRate;
assert(abs(dq.Rate-p.niRate) < 1e-6, 'NI changed the requested rate.');
result.folder = fullfile(p.outputRoot,char(mode+"_"+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))));
assert(~isfolder(result.folder), 'Output folder already exists.');
mkdir(result.folder);
save(fullfile(result.folder,'plan.mat'),'p','s','mode');
if mode ~= "MOTOR", result.previewV = nan(p.ny,p.nx); end
result.hardwareRun = true;


for row = 1:p.ny
    if mode == "MOTOR"
        move(dq,s.forward);
    else
        raw = acquire_row(board,dq,p,s,mode);
        block = reshape(raw,s.samplesPerBin,p.nx);
        previewV = (double(max(block,[],1))-double(min(block,[],1)))*(2*p.rangeV/65535);
        yUm = s.yUm(row);
        save(fullfile(result.folder,sprintf('row_%03d.mat',row)), ...
            'raw','previewV','yUm','row','-v7.3');
        result.previewV(row,:) = previewV;
        clear raw block
    end
    result.rowsDone = row;
    move(dq,s.back);
    if row < p.ny, move(dq,s.yNext); end
end
move(dq,s.yHome);
result.complete = true;
save(fullfile(result.folder,'summary.mat'),'result');
if p.showPlot && mode ~= "MOTOR"
    figure('Name','Voltage-range preview');
    imagesc(s.xUm,s.yUm,result.previewV); axis xy; colorbar;
    xlabel('Nominal X (um)'); ylabel('Commanded Y (um)');
    title(mode+": peak-to-peak voltage (V)");
end
end

function board = open_ats(p)
assert(isfolder(p.sdkFolder), 'Set sdkFolder to the installed ATS SDK Include folder.');
addpath(p.sdkFolder);
AlazarDefs;
alazarLoadLibrary();
board = AlazarGetBoardBySystemID(int32(1),int32(1));
assert(strcmp(AlazarGetBoardKind(board),'ATS9462'), 'This version targets ATS9462.');
[memorySamples,bits] = AlazarGetChannelInfo(board);
assert(double(bits) == 16 && double(memorySamples) > 0, 'Requires 16-bit ATS9462 with onboard memory.');
AlazarSetCaptureClock(board,INTERNAL_CLOCK,SAMPLE_RATE_180MSPS,CLOCK_EDGE_RISING,0);
AlazarInputControlEx(board,CHANNEL_A,DC_COUPLING,INPUT_RANGE_PM_4_V,IMPEDANCE_50_OHM);
AlazarSetBWLimit(board,CHANNEL_A,0);
AlazarSetExternalTrigger(board,DC_COUPLING,ETR_5V);
AlazarSetTriggerOperation(board,TRIG_ENGINE_OP_J,TRIG_ENGINE_J,TRIG_EXTERNAL, ...
    TRIGGER_SLOPE_POSITIVE,p.triggerLevelCode,TRIG_ENGINE_K,TRIG_DISABLE,TRIGGER_SLOPE_POSITIVE,128);
AlazarSetTriggerDelay(board,0);
AlazarSetTriggerTimeOut(board,0);
AlazarConfigureAuxIO(board,AUX_OUT_SERIAL_DATA,0);
end

function raw = acquire_row(board,dq,p,s,mode)
AlazarDefs;
set_direction(dq,s.forward);
if mode == "NPT"
    flags = bitor(ADMA_EXTERNAL_STARTCAPTURE,ADMA_NPT);
    acquisitionRecords = p.nx;
    AlazarSetRecordSize(board,0,s.samplesPerRecord);
else
    flags = bitor(ADMA_EXTERNAL_STARTCAPTURE,ADMA_TRIGGERED_STREAMING);
    acquisitionRecords = hex2dec('7FFFFFFF');
end
bytes = 2*s.bufferSamples;
raw = zeros(s.rowSamples,1,'uint16');
buffers = cell(1,s.ringSize);
try
    for k = 1:s.ringSize, buffers{k} = AlazarAllocBuffer(board,bytes); end
catch err
    release_buffers(board,buffers);
    rethrow(err);
end
rowGuard = onCleanup(@() release_buffers(board,buffers));
AlazarBeforeAsyncRead(board,CHANNEL_A,0,s.samplesPerRecord,s.recordsPerBuffer,acquisitionRecords,flags);
for k = 1:s.ringSize, AlazarPostAsyncBuffer(board,buffers{k},bytes); end
preload(dq,double(s.forward));
AlazarStartCapture(board);
start(dq);
for b = 1:s.bufferTransfers
    k = mod(b-1,s.ringSize)+1;
    AlazarWaitAsyncBufferComplete(board,buffers{k},p.timeoutMs);
    setdatatype(buffers{k},'uint16Ptr',1,s.bufferSamples);
    first = (b-1)*s.bufferSamples+1;
    count = min(s.bufferSamples,s.rowSamples-first+1);
    data = buffers{k}.Value;
    raw(first:first+count-1) = data(1:count);
    if b+s.ringSize <= s.bufferTransfers, AlazarPostAsyncBuffer(board,buffers{k},bytes); end
end
AlazarAbortAsyncRead(board);
clear rowGuard
timer = tic;
while dq.Running
    assert(toc(timer) < size(s.forward,1)/p.niRate+5, 'NI did not finish its finite output.');
    drawnow;
end
read(dq,"all","OutputFormat","Matrix");
end

function move(dq,table)
if isempty(table), return; end
set_direction(dq,table);
readwrite(dq,double(table),"OutputFormat","Matrix");
end

function set_direction(dq,table)

idle = double([0 table(1,2) 0 table(1,4) 0]);
write(dq,idle);
dq.UserData = idle;
end

function close_ni(dq)
try
    stop(dq);
    if ~isempty(dq.UserData), write(dq,dq.UserData); end
catch err
    warning('PAM:NIStop','NI shutdown failed: %s',err.message);
end
end

function release_buffers(board,buffers)
try
    AlazarAbortAsyncRead(board);
catch err
    warning('PAM:Abort','DMA abort failed; buffers retained: %s',err.message);
    return;
end
for k = 1:numel(buffers)
    if isempty(buffers{k}), continue; end
    try
        AlazarFreeBuffer(board,buffers{k});
    catch err
        warning('PAM:Free','Buffer %d was not freed: %s',k,err.message);
    end
end
end
