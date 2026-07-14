# HKUST(GZ) VPN Fix

Fix routing conflicts caused by HKUST(GZ) Sangfor / EasyConnect VPN on Windows.

## Motivation

The school VPN pushes hundreds of public routes into the Windows routing table, forcing most external traffic through the VPN tunnel and making general Internet access slow. This tool removes those unwanted routes and keeps only campus internal subnets (`10/8`, `172.16/12`, `192.168/16`) on the VPN, so external traffic can go through your normal connection / Clash.

## Files

- `fix_sangfor_routes.ps1` — manually clean routes once
- `register_sangfor_auto_clean.ps1` — register an auto-clean scheduled task

## Usage

1. Connect to the school VPN.
2. Open PowerShell **as Administrator**.
3. Run the cleaner manually:

   ```powershell
   .\fix_sangfor_routes.ps1
   ```

   Or register the auto-clean task:

   ```powershell
   .\register_sangfor_auto_clean.ps1
   ```

4. If you registered the task, both `.ps1` files can be deleted afterwards — the cleanup logic is embedded in the scheduled task via `powershell.exe -EncodedCommand`.

## Notes

- Requires Windows administrator privileges.
- No local log files are written.
- If a campus resource becomes unreachable, disconnect and reconnect the VPN to let the task run again, or run `fix_sangfor_routes.ps1` manually.
