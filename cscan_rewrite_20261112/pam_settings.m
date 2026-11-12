function p = pam_settings()

p.runHardware = false;
p.showPlot = true;
p.device = "Dev1";
p.sdkFolder = 'C:\AlazarTech\ATS-SDK\23.3.0\Samples_MATLAB\Include';
p.outputRoot = fullfile(pwd, 'pam_scan_data');

p.niRate = 200e3;          % NI tick = 5 us
p.stepUm = 0.5;
p.xStepTicks = 10;
p.yStepTicks = 100;
p.dxUm = 1;
p.dyUm = 1;
p.nx = 3000;
p.ny = 1;

p.atsRate = 180e6;
p.rangeV = 4;
p.triggerLevelCode = 150;
p.recordSamples = 1024;
p.streamBufferSamples = 524288;
p.bufferCount = 4;
p.timeoutMs = 3000;
p.maxRowMiB = 256;
end
