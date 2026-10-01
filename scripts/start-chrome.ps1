# start-chrome.ps1 opens Chrome with the DevTools endpoint this server needs.
#
# The server reads the page through the DevTools Protocol, which Chrome only
# exposes when it is started with --remote-debugging-port. A separate profile is
# used so the daily driver is left alone and this session's cookies are not
# exposed to whatever else runs on the machine.
#
# Run this once per session, before using the discord_web MCP server. Sign in to
# Discord in the window that opens; it is not automated and no credentials are
# stored by this script.

$ErrorActionPreference = 'Stop'

$port = if ($env:CHROME_DEBUG_PORT) { $env:CHROME_DEBUG_PORT } else { '9222' }
$profile = if ($env:DISCORD_WEB_PROFILE) { $env:DISCORD_WEB_PROFILE } else { Join-Path $env:TEMP 'chrome-discord-web' }

# Locate Chrome.
$candidates = @(
	"$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
	"${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
	"$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$chrome = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) {
	Write-Error 'Chrome was not found in the usual locations.'
	exit 1
}

# Already listening?
try {
	$version = Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/version" -TimeoutSec 3
	Write-Output "Chrome is already listening on $port ($($version.Browser))."
	Write-Output "Using profile: $profile"
	exit 0
} catch {
	# Not running yet, which is the expected path.
}

New-Item -ItemType Directory -Path $profile -Force | Out-Null

Write-Output "starting Chrome with remote debugging on port $port"
Write-Output "profile: $profile"
Write-Output ''

Start-Process -FilePath $chrome -ArgumentList @(
	"--remote-debugging-port=$port",
	"--user-data-dir=$profile",
	'https://discord.com/app'
)

# Wait for the endpoint to answer before reporting success.
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
	Start-Sleep -Milliseconds 500
	try {
		$v = Invoke-RestMethod -Uri "http://127.0.0.1:$port/json/version" -TimeoutSec 2
		Write-Output "DevTools is up: $($v.Browser)"
		$ready = $true
		break
	} catch {
		# Keep waiting.
	}
}

if (-not $ready) {
	Write-Error "Chrome did not open the DevTools endpoint on port $port."
	exit 1
}

Write-Output ''
Write-Output 'Sign in to Discord in the window that just opened, then open the'
Write-Output 'channel you want to read. The server reads whatever tab is in front.'