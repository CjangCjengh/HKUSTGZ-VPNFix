# HKUST(GZ) VPN Fix

修复香港科技大学（广州）Sangfor / EasyConnect 校园 VPN 在 Windows 上的路由冲突。

## 用途

学校 VPN 连接后会往系统路由表里推送大量公网路由，导致外网流量被迫走学校 VPN，速度变慢。这个工具会自动清理这些过量路由，只保留校园内网段（`10/8`、`172.16/12`、`192.168/16`）走学校 VPN，让外网流量恢复正常连接或走 Clash。

## 文件

- `fix_sangfor_routes.ps1` — 手动执行一次路由清理
- `register_sangfor_auto_clean.ps1` — 注册自动清理计划任务

## 使用方法

1. 先连接学校 VPN。
2. 用**管理员身份**打开 PowerShell。
3. 手动清理：

   ```powershell
   .\fix_sangfor_routes.ps1
   ```

   或者注册自动任务：

   ```powershell
   .\register_sangfor_auto_clean.ps1
   ```

4. 注册完自动任务后，两个 `.ps1` 文件都可以删掉——清理逻辑已经通过 `powershell.exe -EncodedCommand` 嵌入到计划任务里了。任务触发后会循环清理 2 分钟（每 10 秒一次），防止 Sangfor 分批推送路由导致漏清。

## 说明

- 需要 Windows 管理员权限。
- 不写任何本地日志文件。
- 如果某些校内资源打不开，可以断开 VPN 重新连接触发自动清理，或者手动运行 `fix_sangfor_routes.ps1`。
