#!/usr/bin/env bash
# Tests the three sample apps on two EastIndia machines (Hyper-V virtual machines), keeps what each step saw in ./evidence/<run>,
# and always removes the machines. <run> is sample-<UTC date and time>, which also names the Compose project.
# Needs: the endia command on the path, able to reach the service; the .NET 10 SDK; jq; curl; and a root image
# tagged lab/win11:base on the EastIndia service (endia base prepare ... --tag lab/win11:base).
set -euo pipefail
cd "$(dirname "$0")"

run="sample-$(date -u +%Y%m%d-%H%M%S)"
evidence="evidence/$run"
mkdir -p "$evidence"
pc() { endia "$@"; }
fleet() { endia compose -p "$run" "$@"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo "== $*"; }

# 1. Build the apps for Windows. They are framework-dependent: the tools layer has the .NET runtimes.
step "publish the sample apps"
for app in SampleService SampleDesktop SampleTray; do
	dotnet publish "$app" -c Release -r win-x64 --self-contained false -o "publish/$app" -v quiet
done

# 2. Build the tools layer over the root image, then the server image over the tools layer, with the service installed.
#    A second build with the same inputs is a cache hit.
step "build sample/tools:1"
mkdir -p tools
[ -f tools/dotnet-install.ps1 ] || curl -fsSL https://dot.net/v1/dotnet-install.ps1 -o tools/dotnet-install.ps1
pc build -t sample/tools:1 -f tools.Endiafile tools
step "build sample/server:1"
cp server.Endiafile publish/Endiafile
pc build -t sample/server:1 publish

# 3. Start the machines that compose.yaml describes, and remove them when the script ends, whether it passed or failed.
step "start the fleet $run"
trap 'step "remove the fleet"; fleet down -v' EXIT
fleet up --wait --wait-timeout 900
fleet ps > "$evidence/ps.txt"
client="$run-client-1"
server="$run-server-1"

# 4. The service: Windows reports it running, and a client reaches it by the server's service name over the private network.
step "check the service"
pc exec "$server" powershell -NoProfile -Command "(Get-Service SampleService -ErrorAction Stop).Status" | tee "$evidence/service-status.txt"
grep -q Running "$evidence/service-status.txt" || fail "SampleService is not running"
[ "$(pc exec "$client" curl.exe -fsS http://server:8080/health)" = healthy ] || fail "the client could not reach the server's health route"

# 5. The desktop app: start it on the client's desktop, wait for its window, drive it by element, keyboard and pointer, and check what it saved.
step "drive the desktop app"
pc exec "$client" cmd /c "mkdir C:\apps"
pc cp publish/SampleDesktop "$client:C:/apps"
pc cp publish/SampleTray "$client:C:/apps"
pid=$(pc desktop launch "$client" 'C:\apps\SampleDesktop\SampleDesktop.exe' | jq -r .processId)
pc desktop wait "$client" "$pid" "Window[Sample Desktop]/Edit#CustomerName" > /dev/null
pc desktop inspect "$client" "$pid" > "$evidence/desktop-ui.json"
pc desktop set-value "$client" "$pid" "Window[Sample Desktop]/Edit#CustomerName" "Ada"
pc desktop invoke "$client" "$pid" "Window[Sample Desktop]/Button[Save]"
[ "$(pc exec "$client" cmd /c type 'C:\ProgramData\EastIndiaSample\saved.txt')" = Ada ] || fail "Save by element did not save Ada"
pc desktop screenshot --pid "$pid" -o "$evidence/desktop-after-invoke.png" "$client"
# Pointer positions count from the window's client area: the text box is at 20,20 (SampleDesktop/Program.cs).
pc desktop pointer "$client" "$pid" click 200,31
pc desktop keys "$client" "$pid" "ctrl+a"
pc desktop keys --text "$client" "$pid" "Grace"
pc desktop click "$client" "$pid" "Window[Sample Desktop]/Button[Save]"
[ "$(pc exec "$client" cmd /c type 'C:\ProgramData\EastIndiaSample\saved.txt')" = Grace ] || fail "typing and clicking Save did not save Grace"
pc desktop screenshot --pid "$pid" -o "$evidence/desktop-after-typing.png" "$client"
# A password box takes a value only as a secret, read from standard input; EastIndia then never reads the value back.
if pc desktop set-value "$client" "$pid" "Window[Sample Desktop]/Edit#Pin" "4321" 2> "$evidence/pin-refused.txt"; then
	fail "the PIN box took a value that was not a secret"
fi
grep -q ACTION_UNSUPPORTED "$evidence/pin-refused.txt" || fail "the PIN box refused a plain value without ACTION_UNSUPPORTED"
[ "$(printf 4321 | pc desktop set-value --secret-stdin "$client" "$pid" "Window[Sample Desktop]/Edit#Pin" | jq -r .value)" = null ] \
	|| fail "set-value read a secret back"
pc desktop click "$client" "$pid" "Window[Sample Desktop]/Button[Save]"
[ "$(pc exec "$client" cmd /c type 'C:\ProgramData\EastIndiaSample\pin.txt')" = 4321 ] || fail "the secret did not reach the PIN box"
pc desktop keys "$client" "$pid" "alt+f4"

# 6. The tray app: it has no window, so check its process in the desktop session and the file it writes every 5 seconds,
#    then close it through its notification-area icon's menu, which is a window of the tray app's own process.
step "check the tray app"
tray=$(pc desktop launch "$client" 'C:\apps\SampleTray\SampleTray.exe' | jq -r .processId)
sleep 6
pc process inspect "$client" "$tray" > "$evidence/tray-process.json"
[ "$(jq -r '.[0].running' "$evidence/tray-process.json")" = true ] || fail "the tray app is not running"
[ "$(jq -r '.[0].sessionId' "$evidence/tray-process.json")" != 0 ] || fail "the tray app is not in the desktop session"
pc exec "$client" cmd /c type 'C:\ProgramData\EastIndiaSample\tray.txt' > "$evidence/tray-heartbeat.txt"
pc desktop tray ls "$client" > "$evidence/tray-icons.txt"
pc desktop tray click --button right "$client" "Sample Tray"
pc desktop wait "$client" "$tray" "Menu/MenuItem[Exit]" > /dev/null
pc desktop screenshot -o "$evidence/desktop.png" "$client"
pc desktop invoke "$client" "$tray" "Menu/MenuItem[Exit]"
[ "$(pc process wait --timeout 30 "$client" "$tray")" = 0 ] || fail "Exit in the tray icon's menu did not end the tray app"

# 7. Evidence: the apps' files, the service's event log entries, the process list and the machines' resource use.
step "collect evidence"
pc cp "$client:C:/ProgramData/EastIndiaSample" "$evidence/client-files"
pc cp "$server:C:/ProgramData/EastIndiaSample" "$evidence/server-files"
pc exec "$server" powershell -NoProfile -Command "Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='SampleService'} | Format-List TimeCreated,Message" > "$evidence/service-events.txt"
pc process ls "$client" > "$evidence/client-processes.txt"
pc stats --no-stream "$client" "$server" > "$evidence/stats.txt"

echo "PASS: evidence in $evidence"
