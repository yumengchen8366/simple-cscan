function result = cscan_triggered_streaming(p) % EN: Entry point for the per-row Triggered Streaming version. | 中文：每行触发一次的 Triggered Streaming 版入口。
if nargin == 0 % EN: Use the example settings when no settings are supplied. | 中文：没有传入参数时使用示例设置。
    p = cscan_settings(); % EN: Read the same settings used by the NPT version. | 中文：读取与 NPT 版共用的参数。
end % EN: Finish the default-settings check. | 中文：结束默认参数判断。
result = run_cscan(p, "TS"); % EN: One trigger starts gapless sampling for each row. | 中文：每行由一个触发启动连续无间断采样。
end % EN: Finish this entry function. | 中文：结束入口函数。
