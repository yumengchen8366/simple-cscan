function s = make_scan_sequence(p, mode) % EN: Build all motion and trigger arrays without touching hardware. | 中文：只生成运动和触发数组，不操作硬件。
assert(ismember(mode, ["NPT", "TS"]), 'Use NPT or TS.'); % EN: Accept only the two implemented modes. | 中文：只接受已经实现的两种模式。
validateattributes(p.nx, {'numeric'}, {'scalar','integer','positive','finite'}); % EN: Require a positive whole number of X positions. | 中文：要求 X 位置数是有限的正整数。
validateattributes(p.ny, {'numeric'}, {'scalar','integer','positive','finite'}); % EN: Require a positive whole number of Y rows. | 中文：要求 Y 行数是有限的正整数。
validateattributes(p.startStep, {'numeric'}, {'scalar','integer','nonnegative','finite'}); % EN: The chosen starting step cannot be negative or fractional. | 中文：指定起始步不能为负数或小数。
assert(all(isfinite([p.stepUm p.dxUm p.dyUm p.speedMmS p.niRate p.settleS])) & all([p.stepUm p.dxUm p.dyUm p.speedMmS p.niRate] > 0), 'Use positive finite motion settings.'); % EN: Reject zero, negative, or nonfinite motion parameters. | 中文：拒绝零值、负值或非有限的运动参数。
assert(p.speedMmS <= 4 & p.settleS >= 0.001, 'This no-ramp example requires speed <= 4 mm/s and settle >= 1 ms.'); % EN: Keep this simple no-ramp design within the historical low-speed range. | 中文：将这个无加速段示例限制在历史低速范围内，并保留方向建立时间。
s.stepTicks = p.niRate * p.stepUm / (1000 * p.speedMmS); % EN: Number of NI time ticks in one motor STEP cycle. | 中文：一个电机 STEP 周期包含的 NI 时钟点数。
s.stepsPerPixel = p.dxUm / p.stepUm; % EN: Convert X spacing from micrometres to motor steps. | 中文：把 X 间距从微米换算为电机步数。
ySteps = p.dyUm / p.stepUm; % EN: Convert one Y row spacing to motor steps. | 中文：把一行 Y 间距换算为电机步数。
counts = [s.stepTicks s.stepsPerPixel ySteps]; % EN: Collect the values that must fit the discrete output grid. | 中文：收集必须落在离散输出网格上的数值。
assert(all(abs(counts-round(counts)) < 1e-9) & s.stepTicks >= 2, 'Choose integer ticks/step and integer steps/spacing.'); % EN: Do not silently round speed or spatial spacing. | 中文：不悄悄舍入速度或空间间距；不合适就报错。
s.stepTicks = round(s.stepTicks); % EN: Remove harmless floating-point roundoff after checking. | 中文：检查后去掉浮点计算产生的微小误差。
s.stepsPerPixel = round(s.stepsPerPixel); % EN: Store an exact integer step count. | 中文：保存精确的整数步数。
ySteps = round(ySteps); % EN: Store the exact integer Y step count. | 中文：保存精确的 Y 整数步数。
s.pixelTicks = s.stepTicks * s.stepsPerPixel; % EN: NI time ticks between successive planned X positions. | 中文：相邻计划 X 位置之间的 NI 时钟点数。
s.pixelSeconds = s.pixelTicks / p.niRate; % EN: Time represented by one X bin. | 中文：每个 X 分箱代表的时间。
s.rowSeconds = p.nx * s.pixelSeconds; % EN: Duration of the retained TS row, measured from its first trigger. | 中文：TS 保留的整行时间长度，从第一个触发开始计算。
s.xSteps = p.startStep + p.nx * s.stepsPerPixel; % EN: Total X motion includes the lead-in steps before the acquisition region. | 中文：X 总运动包括采集区域之前的引入步数。
assert(s.xSteps*p.stepUm <= 5000 & (p.ny-1)*p.dyUm <= 5000, 'Keep this teaching scan within 5 mm per axis.'); % EN: Bound the relative command travel; this does not check the physical stage limits. | 中文：限制相对命令行程；这不能检查滑台当前是否接近物理限位。
s.forward = move_table(s.xSteps, 1, true, p, s.stepTicks); % EN: Make X-forward motion with five output columns. | 中文：生成 X 正向运动，时序表有五列。
s.back = move_table(s.xSteps, 1, false, p, s.stepTicks); % EN: Return X by exactly the commanded forward step count. | 中文：X 回程使用与去程相同的命令步数。
s.yNext = move_table(ySteps, 3, true, p, s.stepTicks); % EN: Move Y forward by one row spacing. | 中文：将 Y 正向移动一个行间距。
s.yHome = move_table((p.ny-1)*ySteps, 3, false, p, s.stepTicks); % EN: Reverse the accumulated Y commands after a successful full scan. | 中文：整幅扫描成功后，反向走完累计的 Y 命令步数。
s.firstTick = round(p.settleS*p.niRate) + p.startStep*s.stepTicks + 1; % EN: MATLAB index of the first trigger; index 1 is time zero. | 中文：第一个触发的 MATLAB 索引；索引 1 对应零时刻。
s.triggerTicks = s.firstTick + (0:p.nx-1)*s.pixelTicks; % EN: Planned NPT trigger indices across one row. | 中文：一行内各个计划 NPT 触发的索引。
if mode == "TS" % EN: Triggered Streaming needs only the first trigger in the row. | 中文：Triggered Streaming 每行只需要第一个触发。
    s.triggerTicks = s.firstTick; % EN: Remove all later trigger commands. | 中文：删除后续所有触发命令。
end % EN: Finish choosing the trigger pattern. | 中文：结束触发模式选择。
s.forward(s.triggerTicks, 5) = true; % EN: Column 5 sends a one-NI-tick pulse at each chosen time. | 中文：第五列在指定时刻输出宽度为一个 NI 时钟点的脉冲。
s.xStartUm = p.startStep*p.stepUm + (0:p.nx-1)*p.dxUm; % EN: Nominal commanded coordinates at the start of each bin. | 中文：每个分箱起始时刻对应的名义命令坐标。
s.yUm = (0:p.ny-1)*p.dyUm; % EN: Relative commanded Y coordinates; the first row is zero. | 中文：相对 Y 命令坐标；第一行为零。
end % EN: Finish building the scan sequence. | 中文：完成扫描时序生成。
function table = move_table(nSteps, stepColumn, direction, p, period) % EN: Build a single X or Y movement with no acquisition triggers. | 中文：生成一段 X 或 Y 运动，不产生采集触发。
lead = round(p.settleS*p.niRate); % EN: Convert the pre/post wait to NI table rows. | 中文：将运动前后等待时间换算为 NI 表格行数。
pattern = [true(floor(period/2),1); false(ceil(period/2),1)]; % EN: One high-then-low STEP cycle; this setup uses the falling edge. | 中文：一个先高后低的 STEP 周期；现有接法使用下降沿。
train = repmat(pattern, nSteps, 1); % EN: Repeat that cycle once for every commanded step. | 中文：每个命令步重复一次这个周期。
table = false(2*lead + numel(train) + 1, 5); % EN: Reserve five columns: X STEP, X DIR, Y STEP, Y DIR, acquisition trigger. | 中文：创建五列：X STEP、X DIR、Y STEP、Y DIR、采集触发。
table(:,2) = true; % EN: Default X direction to the historical positive direction. | 中文：X 方向默认使用历史正向电平。
table(:,4) = true; % EN: Default Y direction to the historical positive direction. | 中文：Y 方向默认使用历史正向电平。
table(:,stepColumn+1) = direction; % EN: Set the direction for the axis that will move. | 中文：设置此次要运动的轴的方向。
table(lead+(1:numel(train)),stepColumn) = train; % EN: Insert the STEP train between the two quiet intervals. | 中文：将 STEP 脉冲串放在前后两个静止等待段之间。
end % EN: Finish the single-movement helper. | 中文：结束单段运动辅助函数。
