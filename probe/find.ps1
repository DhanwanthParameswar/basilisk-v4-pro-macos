$out = 'C:\razercap\find.txt'
$roots = @("$env:USERPROFILE\AppData\Local\Razer\RazerAppEngine\User Data\Apps\Synapse", "C:\Program Files\Razer\RazerAppEngine\app-4.0.896")
"dirs:" | Out-File $out
Get-ChildItem $roots[0] -Directory | % { $_.FullName } | Out-File $out -Append
"hits:" | Out-File $out -Append
Get-ChildItem $roots -Recurse -File -Include *.js,*.json,*.cjs,*.mjs,*.asar -ErrorAction SilentlyContinue |
  ? { $_.Length -lt 200MB } |
  Select-String -Pattern 'Basilisk V4 Pro','"0x00e2"','"0x00E2"','00e2','pid":226\b' -SimpleMatch -List -ErrorAction SilentlyContinue |
  % { '{0} | {1}' -f [int]((Get-Item $_.Path).Length/1kb), $_.Path } | Out-File $out -Append
"done" | Out-File $out -Append
