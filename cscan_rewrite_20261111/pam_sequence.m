function s = pam_sequence(p, mode)

mode = upper(string(mode));
assert(isscalar(mode) && ismember(mode,["NPT","TS","MOTOR"]), 'Use NPT, TS or MOTOR.');
validateattributes([p.nx p.ny], {'numeric'}, {'numel',2,'integer','positive','finite'});
validateattributes([p.xStepTicks p.yStepTicks], {'numeric'}, {'numel',2,'integer','>=',2,'finite'});
validateattributes([p.stepUm p.dxUm p.dyUm p.niRate], {'numeric'}, {'numel',4,'positive','finite'});
steps = [p.dxUm p.dyUm]/p.stepUm;
assert(all(steps >= 1) && all(abs(steps-round(steps)) < 1e-9), 'dxUm and dyUm must be positive whole motor steps.');
s.stepsPerPixel = round(steps(1));
s.ySteps = round(steps(2));
s.xSteps = p.nx*s.stepsPerPixel;
assert(s.xSteps*p.stepUm <= 5000 && (p.ny-1)*p.dyUm <= 5000, 'Commanded travel must stay within 5 mm per axis.');
s.xSpeedMmS = p.stepUm*p.niRate/p.xStepTicks/1000;
s.ySpeedMmS = p.stepUm*p.niRate/p.yStepTicks/1000;
s.pixelTicks = s.stepsPerPixel*p.xStepTicks;
s.pixelSeconds = s.pixelTicks/p.niRate;
s.rowSeconds = p.nx*s.pixelSeconds;
s.xUm = (0:p.nx-1)*p.dxUm;
s.yUm = (0:p.ny-1)*p.dyUm;


s.samplesPerBin = 0; s.samplesPerRecord = 0; s.recordsPerBuffer = 0;
s.rowSamples = 0; s.bufferSamples = 0; s.bufferTransfers = 0; s.ringSize = 0;
if mode ~= "MOTOR"
    assert(p.atsRate == 180e6 && p.rangeV == 4, 'ATS setup is fixed at 180 MS/s and +/-4 V.');
    validateattributes(p.bufferCount, {'numeric'}, {'scalar','integer','>=',2,'<=',16,'finite'});
    validateattributes(p.timeoutMs, {'numeric'}, {'scalar','integer','positive','finite'});
    validateattributes(p.maxRowMiB, {'numeric'}, {'scalar','positive','finite'});
    validateattributes(p.triggerLevelCode, {'numeric'}, {'scalar','integer','>=',0,'<=',255});
    if mode == "NPT"
        validateattributes(p.recordSamples, {'numeric'}, {'scalar','integer','>=',256,'finite'});
        assert(mod(p.recordSamples,32) == 0, 'NPT record length must be a multiple of 32.');
        assert(p.recordSamples/p.atsRate < s.pixelSeconds, 'NPT record must finish before the next trigger.');
        s.samplesPerBin = p.recordSamples;
        s.samplesPerRecord = p.recordSamples;
        s.recordsPerBuffer = gcd(p.nx,10);
    else
        validateattributes(p.streamBufferSamples, {'numeric'}, {'scalar','integer','>=',256,'<=',2^20,'finite'});
        assert(mod(p.streamBufferSamples,32) == 0, 'TS buffer length must be a multiple of 32.');
        samples = s.pixelSeconds*p.atsRate;
        assert(abs(samples-round(samples)) < 1e-6, 'TS bin must contain a whole number of ADC samples.');
        s.samplesPerBin = round(samples);
        s.samplesPerRecord = p.streamBufferSamples;
        s.recordsPerBuffer = 1;
    end
    s.rowSamples = s.samplesPerBin*p.nx;
    s.bufferSamples = s.samplesPerRecord*s.recordsPerBuffer;
    s.bufferTransfers = ceil(s.rowSamples/s.bufferSamples);
    s.ringSize = min(p.bufferCount,s.bufferTransfers);
    assert(2*s.rowSamples <= p.maxRowMiB*2^20, 'Raw row exceeds maxRowMiB; shorten the row or review the memory budget.');
end
s.rowBytes = 2*s.rowSamples;
s.totalRawBytes = s.rowBytes*p.ny;
s.dmaBytes = 2*s.bufferSamples*s.ringSize;


s.forward = move_table(s.xSteps,1,true,p.xStepTicks);
s.back = move_table(s.xSteps,1,false,p.xStepTicks);
s.yNext = move_table(s.ySteps,3,true,p.yStepTicks);
s.yHome = move_table((p.ny-1)*s.ySteps,3,false,p.yStepTicks);
s.triggerTicks = [];
if mode == "NPT", s.triggerTicks = 1+(0:p.nx-1)*s.pixelTicks; end
if mode == "TS", s.triggerTicks = 1; end
s.forward(s.triggerTicks,5) = true;
s.motionSeconds = (2*p.ny*size(s.forward,1) + (p.ny-1)*size(s.yNext,1) + size(s.yHome,1))/p.niRate;
end

function table = move_table(nSteps, column, direction, period)
if nSteps == 0, table = false(0,5); return; end
pulse = [true(floor(period/2),1); false(ceil(period/2),1)];
train = repmat(pulse,nSteps,1);
table = false(numel(train)+1,5);
table(:,[2 4]) = true;
table(:,column+1) = direction;
table(1:numel(train),column) = train;
end
