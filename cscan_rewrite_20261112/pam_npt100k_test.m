function result = pam_npt100k_test(runHardware, nRecords)










if nargin < 1, runHardware = false; end
if nargin < 2, nRecords = 100; end
validateattributes(runHardware, {'logical'}, {'scalar'});
validateattributes(nRecords, {'numeric'}, {'scalar','real','finite','integer','>=',100,'<=',10000});
assert(mod(nRecords,100)==0, 'Use a multiple of 100 records, up to 10000.');
p = pam_settings();
p.runHardware = runHardware;
assert(p.niRate == 200e3 && p.atsRate == 180e6 && p.rangeV == 4 ...
    && p.recordSamples == 1024, 'This short test requires the original clock/range/record settings.');
triggerHz = 100e3;
triggerTable = [repmat([1;0],nRecords,1);0];
recordsPerBuffer = gcd(nRecords,500);
bufferTransfers = nRecords/recordsPerBuffer;
ringSize = min(4,bufferTransfers);
bufferSamples = p.recordSamples*recordsPerBuffer;
bytes = 2*bufferSamples;
assert(p.recordSamples/p.atsRate < 1/triggerHz, 'Record is longer than trigger interval.');
result = struct('complete',false,'hardwareRun',false,'folder','', ...
    'settings',p,'triggerHz',triggerHz,'recordsRequested',nRecords, ...
    'recordsCompleted',0,'triggerTable',triggerTable, ...
    'recordsPerBuffer',recordsPerBuffer,'bufferTransfers',bufferTransfers, ...
    'ringSize',ringSize,'buffersCompleted',0);
fprintf('Stationary NPT: %d triggers at %.0f Hz; interval %.1f us.\n', ...
    nRecords,triggerHz,1e6/triggerHz);
fprintf('NI output %.3f ms; %d samples/record; raw %d bytes.\n', ...
    1e3*numel(triggerTable)/p.niRate,p.recordSamples,2*p.recordSamples*nRecords);
fprintf('DMA: %d records/buffer; %d buffers in ring; %d transfers; %.3f ms/buffer.\n', ...
    recordsPerBuffer,ringSize,bufferTransfers,1e3*recordsPerBuffer/triggerHz);
fprintf('Only port0/line6 is configured; no STEP/DIR or laser output channels.\n');
if ~runHardware, disp('Plan only: no hardware opened.'); return; end
assert(ispc && isfolder(p.sdkFolder), 'Requires laboratory Windows and installed ATS SDK.');
addpath(p.sdkFolder);
AlazarDefs;
alazarLoadLibrary();
board = AlazarGetBoardBySystemID(int32(1),int32(1));
assert(strcmp(AlazarGetBoardKind(board),'ATS9462'), 'Requires ATS9462.');
[~,bits] = AlazarGetChannelInfo(board);
assert(double(bits) == 16, 'Requires 16-bit ADC.');
AlazarSetCaptureClock(board,INTERNAL_CLOCK,SAMPLE_RATE_180MSPS,CLOCK_EDGE_RISING,0);
AlazarInputControlEx(board,CHANNEL_A,DC_COUPLING,INPUT_RANGE_PM_4_V,IMPEDANCE_50_OHM);
AlazarSetBWLimit(board,CHANNEL_A,0);
AlazarSetExternalTrigger(board,DC_COUPLING,ETR_5V);
AlazarSetTriggerOperation(board,TRIG_ENGINE_OP_J,TRIG_ENGINE_J,TRIG_EXTERNAL, ...
    TRIGGER_SLOPE_POSITIVE,p.triggerLevelCode,TRIG_ENGINE_K,TRIG_DISABLE,TRIGGER_SLOPE_POSITIVE,128);
AlazarSetTriggerDelay(board,0);
AlazarSetTriggerTimeOut(board,0);
AlazarConfigureAuxIO(board,AUX_OUT_SERIAL_DATA,0);

dq = daq("ni");
niGuard = onCleanup(@() stop_trigger(dq));
ai = addinput(dq,p.device,"ai1","Voltage");
ai.TerminalConfig = "Differential";
addoutput(dq,p.device,"port0/line6","Digital");
dq.Rate = p.niRate;
assert(abs(dq.Rate-p.niRate)<1e-6, 'NI changed the requested clock rate.');
write(dq,0);
result.folder = fullfile(p.outputRoot, ...
    char("NPT100K_STATIC_"+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))));
assert(~isfolder(result.folder), 'Output folder already exists.');
mkdir(result.folder);
save(fullfile(result.folder,'plan.mat'),'p','nRecords','triggerHz','triggerTable', ...
    'recordsPerBuffer','bufferTransfers','ringSize');

raw = zeros(p.recordSamples,nRecords,'uint16');
buffers = cell(1,ringSize);
try
    for k=1:ringSize, buffers{k} = AlazarAllocBuffer(board,bytes); end
catch err
    release_dma(board,buffers);
    rethrow(err);
end
dmaGuard = onCleanup(@() release_dma(board,buffers));
AlazarSetRecordSize(board,0,p.recordSamples);
AlazarBeforeAsyncRead(board,CHANNEL_A,0,p.recordSamples,recordsPerBuffer,nRecords, ...
    bitor(ADMA_EXTERNAL_STARTCAPTURE,ADMA_NPT));
for k=1:ringSize, AlazarPostAsyncBuffer(board,buffers{k},bytes); end
preload(dq,triggerTable);
AlazarStartCapture(board);
result.hardwareRun = true;
try
    start(dq);
    for b=1:bufferTransfers
        k = mod(b-1,ringSize)+1;
        AlazarWaitAsyncBufferComplete(board,buffers{k},p.timeoutMs);
        setdatatype(buffers{k},'uint16Ptr',1,bufferSamples);
        columns = (b-1)*recordsPerBuffer+(1:recordsPerBuffer);
        raw(:,columns) = reshape(buffers{k}.Value,p.recordSamples,recordsPerBuffer);
        result.buffersCompleted = b;
        result.recordsCompleted = b*recordsPerBuffer;
        if b+ringSize <= bufferTransfers
            AlazarPostAsyncBuffer(board,buffers{k},bytes);
        end
    end
catch err
    clear niGuard dmaGuard
    raw = raw(:,1:result.recordsCompleted);
    result.errorMessage = err.message;
    save(fullfile(result.folder,'partial.mat'),'raw','result');
    rethrow(err);
end
AlazarAbortAsyncRead(board);
clear dmaGuard
timer = tic;
while dq.Running
    assert(toc(timer)<5, 'NI finite trigger output did not finish.');
    drawnow;
end
read(dq,"all","OutputFormat","Matrix");
clear niGuard

result.recordsCompleted = size(raw,2);
result.complete = true;

save(fullfile(result.folder,'capture.mat'),'raw','result');
v = (double(raw)-32767.5)*(p.rangeV/32767.5);
above = v>0.5;
result.edgesPerRecord = sum(above(2:end,:)&~above(1:end-1,:),1);
result.singlePulseRecords = sum(result.edgesPerRecord==1);
result.railSamples = sum(raw(:)==0 | raw(:)==65535);
result.vpp = max(v,[],1)-min(v,[],1);
result.edgeUs = nan(1,nRecords);
for k=1:nRecords
    idx = find(above(2:end,k)&~above(1:end-1,k),1)+1;
    if ~isempty(idx), result.edgeUs(k) = (idx-1)/p.atsRate*1e6; end
end
save(fullfile(result.folder,'capture.mat'),'raw','result');
fprintf('Completed %d/%d records; exactly one >0.5 V rising edge: %d/%d; rail samples: %d.\n', ...
    result.recordsCompleted,nRecords,result.singlePulseRecords,nRecords,result.railSamples);
fprintf('Vpp range %.6g to %.6g V. Saved: %s\n',min(result.vpp),max(result.vpp),result.folder);
if result.singlePulseRecords ~= nRecords
    warning('PAM:PulseCheck','Capture completed, but some records do not contain exactly one test pulse.');
end
if p.showPlot
    figure('Name','Stationary NPT 100 kHz: first, middle, last');
    selected = [1 ceil(nRecords/2) nRecords];
    plot((0:p.recordSamples-1)'/p.atsRate*1e6,v(:,selected));
    xlabel('Time after ATS trigger (us)'); ylabel('Voltage (V)');
    legend(compose('Record %d',selected)); grid on;
end
end

function stop_trigger(dq)
try
    stop(dq);
catch err
    warning('PAM:StopTrigger','NI stop failed: %s',err.message);
end
try
    write(dq,0);
catch err
    warning('PAM:TriggerLow','Could not set P0.6 low: %s',err.message);
end
end

function release_dma(board,buffers)
try
    AlazarAbortAsyncRead(board);
catch err
    warning('PAM:Abort','DMA abort failed; buffer retained: %s',err.message);
    return;
end
for k=1:numel(buffers)
    if isempty(buffers{k}), continue; end
    try
        AlazarFreeBuffer(board,buffers{k});
    catch err
        warning('PAM:Free','DMA buffer %d release failed: %s',k,err.message);
    end
end
end
