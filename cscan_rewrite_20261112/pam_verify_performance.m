function pam_verify_performance(baselineDir, newDir)


thisDir = fileparts(mfilename('fullpath'));
if nargin < 1
    baselineDir = fullfile(fileparts(thisDir),'cscan_rewrite_20261111');
end
if nargin < 2
    newDir = thisDir;
end
originalDir = pwd;
originalPath = path;
restoreGuard = onCleanup(@() restore_environment(originalDir,originalPath));
assert(isfolder(baselineDir) && isfolder(newDir), 'Both version folders must exist.');
outputRoot = tempname;
assert(~isfolder(outputRoot), 'Offline output marker unexpectedly exists.');

names = ["default", "short_one_row", "short_y_motion", "timing_run", ...
    "long_scan_geometry", "odd_step_ticks", "buffer_tail", "five_mm_rows"];
settings = {struct(), struct('nx',200,'ny',1), ...
    struct('nx',200,'ny',3,'dyUm',100), struct('nx',2500,'ny',20), ...
    struct('nx',2500,'ny',2500), struct('nx',2500,'ny',3,'xStepTicks',11), ...
    struct('nx',201,'ny',3), struct('nx',5000,'ny',3)};
modes = ["NPT", "TS", "MOTOR"];
fields = {'forward','back','yNext','yHome','triggerTicks','rowSamples','bufferTransfers'};
before = collect_plans(baselineDir,settings,modes,outputRoot);
after = collect_plans(newDir,settings,modes,outputRoot);
passed = 0;
for k = 1:numel(settings)
    for m = 1:numel(modes)
        a = before{k,m}; b = after{k,m};
        for f = 1:numel(fields)
            key = fields{f};
            assert(isequal(a.(key),b.(key)), '%s / %s: %s changed.', ...
                names(k),modes(m),key);
        end
        assert(isequal(a,b), '%s / %s: another sequence field changed.',names(k),modes(m));
        fprintf('PASS %-20s %-5s seven required fields + complete sequence equal\n',names(k),modes(m));
        passed = passed + 1;
    end
end


invalid = {struct('xStepTicks',1), struct('xStepTicks',2.5), ...
    struct('dxUm',0.75), struct('nx',5001), struct('nx',5000,'xStepTicks',20)};
invalidModes = ["NPT", "NPT", "NPT", "NPT", "TS"];
invalidNames = ["tick_below_two", "noninteger_tick", "fractional_motor_step", ...
    "travel_over_five_mm", "ts_row_over_budget"];
for k = 1:numel(invalid)
    firstError = rejected_plan(baselineDir,invalid{k},invalidModes(k));
    secondError = rejected_plan(newDir,invalid{k},invalidModes(k));
    assert(strcmp(firstError,secondError), 'Validation changed for %s.',invalidNames(k));
    fprintf('PASS validation %-24s both versions reject identically\n',invalidNames(k));
end
assert(~isfolder(outputRoot), 'A plan-only call created an output directory.');
fprintf('\nPASS: %d plan comparisons, %d invalid-input checks; no output directory created.\n', ...
    passed,numel(invalid));
fprintf('Scope: planned waveforms and counts only. Runtime overlap, DMA lifetime and hardware speed: NOT TESTED.\n');
end

function plans = collect_plans(folder,settings,modes,outputRoot)
select_version(folder);
fprintf('\nTesting version: %s\n',folder);
fprintf('pam_settings: %s\npam_sequence: %s\npam_scan: %s\n', ...
    which('pam_settings'),which('pam_sequence'),which('pam_scan'));
plans = cell(numel(settings),numel(modes));
for k = 1:numel(settings)
    p = pam_settings();
    assert(isequal(p.runHardware,false), 'Default runHardware must remain false.');
    p.runHardware = false;
    p.showPlot = false;
    p.outputRoot = outputRoot;
    keys = fieldnames(settings{k});
    for f = 1:numel(keys), p.(keys{f}) = settings{k}.(keys{f}); end
    for m = 1:numel(modes)
        mode = modes(m);
        s = pam_sequence(p,mode);
        assert(~p.runHardware, 'Hardware execution is forbidden in this test.');
        evalc('result = pam_scan(mode,p);');
        assert(isequal(result.sequence,s), 'pam_scan returned a different plan.');
        assert(~result.hardwareRun && ~result.complete && result.rowsDone==0, ...
            'Plan-only status is inconsistent.');
        assert(isempty(result.folder), 'Plan-only mode returned an output folder.');
        plans{k,m} = s;
    end
end
end

function message = rejected_plan(folder,overrides,mode)
select_version(folder);
p = pam_settings();
assert(isequal(p.runHardware,false), 'Default runHardware must remain false.');
keys = fieldnames(overrides);
for f = 1:numel(keys), p.(keys{f}) = overrides.(keys{f}); end
message = '';
try
    pam_sequence(p,mode);
catch err
    message = err.message;
end
assert(~isempty(message), 'An invalid input was accepted.');
end

function select_version(folder)
cd(folder);
clear pam_settings pam_sequence pam_scan
rehash;
for name = ["pam_settings", "pam_sequence", "pam_scan"]
    expected = fullfile(folder,char(name + ".m"));
    assert(strcmp(which(char(name)),expected), 'Wrong function selected: %s',name);
end
end

function restore_environment(originalDir,originalPath)
cd(originalDir);
path(originalPath);
clear pam_settings pam_sequence pam_scan
end
