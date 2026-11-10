function result = cscan_npt(p) % EN: Entry point for the NPT version; return a result structure. | 中文：NPT 版入口；返回包含结果的结构体。
if nargin == 0 % EN: If you supplied no settings, use the example settings. | 中文：如果没有传入参数，就使用示例设置。
    p = cscan_settings(); % EN: Get the editable settings from one small function. | 中文：从一个小函数读取可修改的参数。
end % EN: Finish the default-settings check. | 中文：结束默认参数判断。
result = run_cscan(p, "NPT"); % EN: Run the raster using one short record per planned X position. | 中文：执行栅格扫描，每个计划 X 位置采一条短记录。
end % EN: Finish this entry function. | 中文：结束入口函数。
