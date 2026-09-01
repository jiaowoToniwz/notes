$ErrorActionPreference = 'Stop'
$src = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
$dst = 'D:\Notes\notes.exe'
$ahk = 'D:\Notes\notes.ahk'

Copy-Item $src $dst -Force

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$scriptBytes = $utf8NoBom.GetBytes([System.IO.File]::ReadAllText($ahk))

Add-Type -Namespace W -Name U -MemberDefinition @"
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr BeginUpdateResource(string pFileName, bool bDeleteExistingResources);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool UpdateResource(IntPtr hUpdate, IntPtr lpType, IntPtr lpName, short wLanguage, byte[] lpData, uint cb);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool EndUpdateResource(IntPtr hUpdate, bool fDiscard);
"@

$h = [W.U]::BeginUpdateResource($dst, $false)
if ($h -eq [IntPtr]::Zero) { throw "BeginUpdateResource failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
$ok = [W.U]::UpdateResource($h, [IntPtr]10, [IntPtr]1, 0x0409, $scriptBytes, [uint32]$scriptBytes.Length)
if (-not $ok) { throw "UpdateResource failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
$ok2 = [W.U]::EndUpdateResource($h, $false)
if (-not $ok2) { throw "EndUpdateResource failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }

Write-Output "OK bytes=$($scriptBytes.Length)"
