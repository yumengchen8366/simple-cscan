function w = pam_waveform(folder, row, bin)

if nargin < 2, row = 1; end
if nargin < 3, bin = 1; end
a = load(fullfile(folder,'plan.mat'),'p','s','mode');
assert(a.mode ~= "MOTOR", 'MOTOR runs have no ADC data.');
validateattributes(row,{'numeric'},{'scalar','integer','>=',1,'<=',a.p.ny});
validateattributes(bin,{'numeric'},{'scalar','integer','>=',1,'<=',a.p.nx});
f = matfile(fullfile(folder,sprintf('row_%03d.mat',row)));
assert(isequal(size(f,'raw'),[a.s.rowSamples 1]), 'Saved row length does not match its plan.');
n = a.s.samplesPerBin;
first = (bin-1)*n+1;
codes = f.raw(first:first+n-1,1);
w.timeUs = (0:n-1)'/a.p.atsRate*1e6;
w.volts = (double(codes)-32767.5)*(a.p.rangeV/32767.5);
w.minV = min(w.volts); w.maxV = max(w.volts);
w.vpp = w.maxV-w.minV;
w.nominalXUm = a.s.xUm(bin);
w.row = row; w.bin = bin; w.mode = a.mode;
fprintf('Row %d bin %d: %d samples; min %.6g V; max %.6g V; Vpp %.6g V.\n', ...
    row,bin,n,w.minV,w.maxV,w.vpp);
figure('Name','Measured ADC waveform');
plot(w.timeUs,w.volts); grid on;
xlabel('Time within record / bin (us)'); ylabel('Voltage (V)');
title(sprintf('%s: row %d, bin %d',a.mode,row,bin));
end
