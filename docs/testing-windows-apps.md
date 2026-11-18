# Testing networked Windows applications with EastIndia

This guide is for teams, and their automated agents, who need to test a Windows application on real Windows: a Windows service, a desktop program, a notification-area (tray) program, or several of them talking over a network. It shows how a test creates Windows machines, installs the application, drives its screen with the mouse and keyboard, takes screenshots, collects evidence and removes everything afterwards. Every command here has been run against a live EastIndia service.

`samples/windows-app-testing/` holds a complete working example: a Windows service, a desktop program and a tray program, an image recipe, a Compose file and `run-tests.sh`, a test script that uses everything below. Reading that script beside this guide is the quickest way in.

## How EastIndia works

EastIndia runs Windows virtual machines for tests, the way Docker runs containers. One Windows PC with Hyper-V runs the **EastIndia service**. Your test talks to the service with the **`endia` command line**, which takes Docker's commands and options wherever Docker has one.

* An **image** is a Windows disk that machines start from. Images form layers: a recipe in Dockerfile syntax adds software to a parent image, as `docker build` does.
* A **machine** is a Hyper-V virtual machine, created from an image on a new disk of its own. Removing it deletes that disk and leaves the image unchanged.
* A **fleet** is the set of machines, private networks and volumes that one Compose file describes. `endia compose up` creates it and `endia compose down` removes it. EastIndia has no `endia run`: every machine comes from a Compose file.

Each machine runs Windows with a desktop user, `testuser`, who is signed in automatically, so the screen is live as soon as the machine is ready. Commands reach into the machine through two programs that every image holds: a guest service, which runs programs and copies files, and a desktop helper, which works the screen, keyboard and mouse in `testuser`'s session.

## Before you start

You need three things from whoever runs the EastIndia PC:

1. **A context file**, `<name>.eastindiacontext`. It holds the service's address and a client certificate. The PC's owner makes it with `endia context export <name>` on the PC; the certificate lasts 365 days.
2. **Network access to the service.** From a Docker sandbox on the PC, the service is at `host.docker.internal:7443`, and the sandbox's policy must allow `localhost:7443` (`sbx policy allow network --sandbox <sandbox> localhost:7443`, run on the PC). The same applies to every port you publish from a machine, described in "Networks".
3. **The `endia` command line** for your platform. For Linux, download `endia-linux-x64` from the [Releases page](https://github.com/teaToolkit/EastIndia/releases).

Then, in your environment:

```sh
endia context import pc <name>.eastindiacontext
endia context use pc
endia version     # prints the command line's and the service's versions
endia images      # lists the images you can start machines from
```

`endia version` exits with 1 and names the cause when the service cannot be reached or refuses the certificate. Instead of a context, `EASTINDIA_HOST=tcp://host.docker.internal:7443` and `EASTINDIA_CERT_PATH=<folder holding ca.pem, cert.pem and key.pem>` work as `DOCKER_HOST` and `DOCKER_CERT_PATH` do.

### The Python client

A test written in Python can call the service through the `endia` package on PyPI instead of running the command line:

```sh
pip install endia
```

```python
from endia import EastIndiaClient

with EastIndiaClient.from_env() as client:
    for machine in client.machines.list():
        print(machine)
```

`EastIndiaClient.from_env()` connects as `endia` does: with `EASTINDIA_HOST` and `EASTINDIA_CERT_PATH` when they are set, then the context that `EASTINDIA_CONTEXT` names, then the current context, from `EASTINDIA_CONFIG` or `~/.eastindia`. Until EastIndia 0.16.80 the package was shipped as a wheel named `eastindia_client`. `endia` has every public class and function that package had, and reads the same environment variables, so moving to it means changing the import from `eastindia_client` to `endia`.

### The images you start from

EastIndia ships no Windows images. The PC's owner prepares a root image once, from Microsoft's Windows 11 IoT Enterprise LTSC evaluation ISO, with `endia base prepare` ("Building and layering images" in [Using EastIndia](using-eastindia.md) shows how). This guide calls it `lab/win11:base`. It holds Windows, EastIndia's guest service and desktop helper, an OpenSSH server and `curl.exe`, and two accounts: `testuser`, a standard user signed in automatically, and `testadmin`, an administrator.

Build two layers over the root image:

1. **A tools layer.** It installs the runtimes your application needs, and sets the registry line that moves elevation prompts onto the normal desktop, where EastIndia can answer them (see "Elevation prompts"). The sample's `tools.Endiafile` installs the .NET 10 runtime and its desktop runtime and sets that line; `run-tests.sh` builds it as `sample/tools:1`.
2. **Your application's image** over the tools layer (see "Images for your application").

Windows Update is off in the root image. A machine is short-lived, so updating Windows would only spend the machine's processor time, memory and network on work that is thrown away with it. Microsoft Defender still looks for its own updates, and its downloads fail.

The evaluation edition stops working 90 days after its root image was prepared. Each image records the date in its `eastindia.evaluation.expires` label, and `endia images` warns as that date approaches. Its desktop shows the edition and its licence status as a watermark in the bottom-right corner, which appears in screenshots. On a machine's first boot the watermark wrongly says 'Windows License is expired'; Windows' licensing still counts the machine as licensed, and after a restart the watermark gives the days left. The wrong text does not affect tests.

## The shape of a test

A test follows the same steps every time:

1. **Build an image** with the application installed, or use a stock image and copy the application in later.
2. **Start the machines** with `endia compose up --wait`.
3. **Install or start** the parts that the image does not already run.
4. **Act and check**: call the application over the network, run programs in the machine, drive its desktop.
5. **Collect evidence**: screenshots, files, logs, event-log entries.
6. **Remove the machines** with `endia compose down -v`, whether the test passed or not.

Give each run a project name of its own, so that runs side by side never touch each other's machines, and remove the fleet from a shell trap:

```sh
set -euo pipefail
run="mytest-$(date -u +%Y%m%d-%H%M%S)"
trap 'endia compose -p "$run" down -v' EXIT
endia compose -p "$run" up --wait --wait-timeout 900
```

Say what the run is for and how far it has got, so that whoever watches the desktop app's Home page can tell a slow run from a stuck one. Give the purpose to `up` with `--purpose "Regression run 412"`: a short title in plain words that a person reads on Home, with file names, folders and test IDs kept for the notes file (`--purpose-file`). Then report each stage and count with `endia update` as the script goes:

```sh
endia update "$run" --stage "Run tests 2/2" --workload 120
endia update "$run-client-1" --progress 30
```

EastIndia never estimates progress: Home's bar moves only when the script reports a count. The user guide in this folder, `using-eastindia.md`, gives the rules in its section 'Saying what a fleet is for and how far it has got', such as which of the fleet or its machines holds the total.

Machines are named `<project>-<service>-<n>`, so the first `client` machine of that run is `$run-client-1`. `up` builds a service's image from its `build` section when the image is missing. `--no-build` builds nothing, so a missing image fails with `NOT_FOUND`; `--build` builds every service that has `build`, even if its image exists.

Every command exits with 0 on success, 1 on a failure, 125 when the command line itself was wrong (nothing was sent) and 130 after Ctrl+C. On a failure, standard error says why. `Error response from EastIndia: <message> (<CODE>)` means the service refused the request. `Cannot connect to the EastIndia service at <address>. Is the service running?` means the command could not reach the service. `--format json` turns any listing into JSON for a program to read.

## Images for your application

A recipe is an Endiafile, a file in Dockerfile syntax. It installs your application and the Windows settings it needs on top of a parent image. This one, `samples/windows-app-testing/server.Endiafile`, installs a Windows service that starts with Windows and opens its port in the Windows firewall:

```dockerfile
# escape=`
FROM sample/tools:1
SHELL ["powershell.exe", "-NoProfile", "-Command"]
COPY SampleService/ C:/apps/SampleService/
RUN New-Service -Name SampleService -BinaryPathName 'C:\apps\SampleService\SampleService.exe' -StartupType Automatic | Out-Null
RUN New-NetFirewallRule -DisplayName SampleService -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8080 | Out-Null
```

```sh
endia build -t sample/server:1 -f server.Endiafile ./publish
```

A recipe's file is `Endiafile`, or `name.Endiafile` when a folder holds several. Without `-f`, `endia build` reads `Endiafile` in the build context, or `Dockerfile` when there is no `Endiafile`; `-f` takes a file of any name, so a recipe kept as `name.Dockerfile` still builds. The files a build leaves out of the context are listed in `.endiaignore` or, failing that, `.dockerignore`; a recipe can have its own beside it, such as `server.Endiafile.endiaignore`, which comes first.

**Tip: highlighting in VS Code.** VS Code recognises `Dockerfile` by name but not `Endiafile`. To give Endiafiles Dockerfile highlighting, add this to your settings (File › Preferences › Settings, then the Open Settings (JSON) button):

```json
"files.associations": {
  "Endiafile": "dockerfile",
  "*.Endiafile": "dockerfile"
}
```

The last argument is the build context, the folder that `COPY` reads from; the command line sends it to the service. The build prints Docker's classic output, `Step n/m : ...`, and ends with `Successfully tagged sample/server:1`. Building this recipe took 29 seconds. Building the same recipe with the same inputs again reuses the image (`Using cache:`); `--no-cache` builds it afresh.

* `RUN` steps run as SYSTEM, can reach the internet, and may take up to 30 minutes each. A step that exits with 3010 restarts the machine and the build carries on.
* `SHELL ["powershell.exe", ...]` is Windows PowerShell 5.1. Without `SHELL`, a step runs through `cmd /S /C`.
* `ADD`, `VOLUME`, `HEALTHCHECK`, here-documents and options on `COPY` and `RUN` are refused with `UNSUPPORTED_FIELD`, naming the line.

**Bake or copy?** Bake into an image what every run needs and what changes rarely: runtimes, the service's installation, firewall rules, registry settings. Copy into a running machine what changes on every run, such as the build under test (see "Deploying into a running machine"). A machine starts from an image in about 20 seconds; installing software into every machine on every run costs that time again each run.

## Creating and starting machines

A Compose file describes the machines. This one, `samples/windows-app-testing/compose.yaml`, has one server running the service from the image above, and one client whose desktop the test drives:

```yaml
services:
  server:
    image: sample/server:1
    healthcheck:
      test: ["CMD", "curl.exe", "-fs", "http://127.0.0.1:8080/health"]
      interval: 5s
    networks: [lab]
  client:
    image: sample/tools:1
    depends_on:
      server:
        condition: service_healthy
    networks: [lab]
networks:
  lab: {}
```

```sh
endia compose -p "$run" up --wait --wait-timeout 900
endia compose -p "$run" ps
```

`up --wait` returns when every machine is running and ready, and healthy when it has a health check. Ready means Windows has booted, `testuser` is signed in and the desktop helper is running. Here the server started first; the client started once the server's health check passed. The whole fleet took 49 seconds; one machine alone takes about 20. If a machine fails its health check, or the wait passes `--wait-timeout` seconds, `up` exits with 1.

* **Size.** A machine starts with 2 GiB of memory and grows to its `mem_limit`, or to 4 GiB when none is set. `cpus` sets its processors (default 2). Less than 2 GiB is refused.
* **Replicas.** `deploy: replicas: 3` gives `client-1` to `client-3`. Commands that act on one replica take `--index`, as in `endia compose exec --index 2 client ...`.
* **Main process.** A service with no `command` or `entrypoint` keeps running until you stop it, which suits most tests. A service with a `command` behaves like a container: when the program exits, the machine shuts down.
* **Other keys.** `build`, `entrypoint`, `environment`, `env_file`, `hostname`, `container_name`, `user`, `working_dir`, `labels`, `extra_hosts`, `restart`, `ports`, `expose`, `volumes` and bind mounts, `cpus`, `mem_limit`, `stop_grace_period`, `platform` and `x-eastindia` are accepted; any other key is refused with `UNSUPPORTED_FIELD` and its name. `endia compose config` prints the file as EastIndia reads it.

## Networks

* **Between machines.** Each network in the Compose file is a private Hyper-V switch with its own addresses (by default from `10.231.0.0/16`). Machines on the same network reach each other by service name, because EastIndia writes the fleet's names into every machine's hosts file, between the lines `# eastindia begin` and `# eastindia end`. In the sample, the client reached the server with `curl.exe http://server:8080/health`. Windows' firewall in the server must let the port in, as the recipe's `New-NetFirewallRule` does.
* **To the internet and the PC.** Every machine also has a card named `internet` on the PC's `Default Switch`, unless all its networks are marked `internal: true`. Through it the machine reaches the internet and the PC itself. To reach a service on the PC, such as a database in Docker, give the PC a name with `extra_hosts: ["pc=host-gateway"]`. The service on the PC must listen on all of the PC's addresses, not only `127.0.0.1`, and the PC's firewall must let the connection in from the Default Switch.
* **From your test to a machine.** Publish a port: `ports: ["18080:8080"]` listens on the PC's `127.0.0.1:18080` and forwards to the machine's port 8080. From a sandbox, connect to `host.docker.internal:18080` once the sandbox's policy allows `localhost:18080`. A port given without a published number gets a free one; `endia inspect <machine>` shows which.

## Running programs and copying files

```sh
endia exec "$run-server-1" powershell -NoProfile -Command "(Get-Service SampleService -ErrorAction Stop).Status"
endia exec "$run-client-1" curl.exe -fsS http://server:8080/health
```

`exec` runs a program in the machine, prints its output and exits with its exit code. It runs as SYSTEM, outside the desktop, so it cannot show a window; use `desktop launch` for that. `-d` starts the program and returns its process ID at once, `-u` runs it as another local account, and `-w` and `-e` set its folder and environment. Add `-ErrorAction Stop` to a PowerShell command that must fail the `exec` when it fails, because PowerShell's exit code is that of its last statement.

```sh
endia exec "$run-client-1" cmd /c "mkdir C:\apps"
endia cp ./publish/SampleDesktop "$run-client-1:C:/apps"            # the folder itself, into C:\apps
endia cp ./publish/. "$run-client-1:C:/apps"                         # the folder's contents
endia cp "$run-client-1:C:/ProgramData/EastIndiaSample" ./evidence   # back out of the machine
```

`cp` follows Docker's rules. The destination folder in the machine must exist first.

## Installing a Windows service and checking it runs

Install it in the image, as `server.Endiafile` does, or into a running machine:

```sh
m="$run-client-1"
endia exec "$m" cmd /c "mkdir C:\apps"
endia cp ./publish/SampleService "$m:C:/apps"
endia exec "$m" sc.exe create SampleService binPath= "C:\apps\SampleService\SampleService.exe" start= auto
endia exec "$m" sc.exe start SampleService
endia exec "$m" powershell -NoProfile -Command "(Get-Service SampleService).WaitForStatus('Running','00:00:30'); (Get-Service SampleService).Status"
```

Check it in three ways, from the weakest to the strongest:

1. **Windows says it runs:** `Get-Service` above prints `Running`, or `sc.exe query SampleService` shows `STATE : 4 RUNNING`.
2. **It does its job:** call it, from inside the machine (`endia exec "$m" curl.exe -fsS http://127.0.0.1:8080/health`), from another machine by name, or from your test through a published port.
3. **It logged what you expect:** read the Windows event log, where a .NET service writes under its own name:

   ```sh
   endia exec "$m" powershell -NoProfile -Command "Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='SampleService'} -MaxEvents 5 | Format-List TimeCreated,Message"
   ```

An MSI installs the same way: copy it in, then `endia exec "$m" msiexec /i C:\apps\MyApp.msi /quiet /norestart`. `msiexec /x ... /quiet` removes it.

## Installing a desktop or tray program and checking it runs

Copy the program in with `cp`, as above, or bake it into the image. Then start it on `testuser`'s desktop:

```sh
pid=$(endia desktop launch "$m" 'C:\apps\SampleDesktop\SampleDesktop.exe' | jq -r .processId)
```

`desktop launch` prints JSON: the process ID (`processId`), its start time, its session (1, `testuser`'s), its user, its integrity level and its windows. Put `--` before program arguments that start with `-`. `--elevated` asks for administrator rights, which `testuser`, a standard user, does not have; for a program that asks for elevation itself, answer the prompt as "Elevation prompts" describes.

**Waiting for a program to finish.** `endia process wait "$m" "$pid"` waits until the process ends and prints its exit code, as `docker wait` does. It works for a program started by `desktop launch` or `exec -d`. EastIndia knows the exit code only of a program it started since the machine last booted, so for any other process the command fails. `--timeout <seconds>` limits the wait. When the time passes first, the command exits with 1 and writes `Error response from EastIndia: Process <pid> was still running after <seconds> seconds. (TIMEOUT)` to standard error, and the process keeps running.

On success, `process wait` exits with 0 and prints only the exit code, followed by a line break. It prints the code in full, never reduced to 256 values: 3010 prints as `3010`. Windows exit codes from 0x80000000 upwards print as negative numbers, so a crash with 0xC0000005 prints as `-1073741819`.

```sh
code=$(endia process wait --timeout 180 "$m" "$pid")   # 0 when the program succeeded
```

**Telling a program's exit code from a EastIndia failure.** `exec` exits with the program's own exit code, so an exit code alone cannot say whether 1, 125, 126, 127 or 130 came from the program or from EastIndia. Standard error does not settle it either, because the program's own error output arrives there too. To keep the two apart, start the program with `exec -d` and wait for it with `process wait`. Each of the two commands exits with 0 when its request succeeds. When the service refuses the request or cannot be reached, the command exits with 1 and writes a EastIndia message to standard error. A program that is not found, or cannot start, makes `exec -d` fail with `NOT_FOUND` or `CAPABILITY_MISSING`. The program's exit code appears only on `process wait`'s standard output. `endia process logs "$m" "$pid"` prints what the program wrote.

```sh
pid=$(endia exec -d "$m" msiexec /i C:\apps\MyApp.msi /quiet /norestart)
code=$(endia process wait "$m" "$pid")   # 3010: installed, restart needed
```

**A desktop program** shows a window, so check both that its process runs and that its window is up:

```sh
endia process inspect "$m" "$pid" | jq '.[0] | {running, sessionId, windows: [.windows[] | select(.visible) | .title]}'
endia desktop windows "$m"     # every visible window: process, handle, position, size, title
```

**A tray program** has no visible window, only an icon in the notification area. Check that its process runs in the desktop session, and check something it does, such as a file, a log line or a port it opens:

```sh
tray=$(endia desktop launch "$m" 'C:\apps\SampleTray\SampleTray.exe' | jq -r .processId)
endia process inspect "$m" "$tray" | jq '.[0] | {running, sessionId}'   # running: true, sessionId: 1
endia exec "$m" cmd /c type C:\ProgramData\EastIndiaSample\tray.txt    # the time it last wrote
```

To work the icon itself, use `desktop tray`. The icon belongs to the Windows taskbar, not to the tray program, so the commands that take a process ID cannot reach it. Windows hides new icons behind the "Show hidden icons" arrow; `desktop tray` finds them there too. The menu the icon opens is a window of the tray program's own process, so the element commands take over from there:

```sh
endia desktop tray ls "$m"                                         # NAME and HIDDEN of every icon
endia desktop tray click --button right "$m" "Sample Tray"        # opens the hidden icons when it must
endia desktop wait "$m" "$tray" "Menu/MenuItem[Exit]"              # the menu is the tray program's window
endia desktop invoke "$m" "$tray" "Menu/MenuItem[Exit]"
```

**The menu's window is not always a `Menu`.** What a menu looks like to UI Automation depends on the framework that draws it, so open the menu once and look before writing the selector: `endia desktop inspect "$m" "$tray"`. The sample's menu is a Windows menu: its window's control type is `Menu`, and its items answer `invoke`. Avalonia draws its tray menu in an ordinary window of control type `Window`, named `Window`, with a `List` inside and the `MenuItem`s inside that. For such a menu `Menu/MenuItem[Exit]` finds no window; use `Window/MenuItem[Exit]`. Avalonia's items do not answer `invoke` (`ACTION_UNSUPPORTED`), so use `desktop click`, which clicks the item with the pointer:

```sh
endia desktop wait "$m" "$tray" "Window/MenuItem[Exit]"            # a menu drawn by Avalonia
endia desktop click "$m" "$tray" "Window/MenuItem[Exit]"
```

An icon's name is the program's tooltip, and many programs add their state to it, so `tray click` takes the start of the name: `"Sample Tray"` also matches `Sample Tray: connected`. A name that matches no icon, or several, is refused with the names of the icons there are. Copy the name as `desktop tray ls` prints it: some programs' names begin with a space, which the start of the name must then include.

## Driving the screen

Prefer acting on named elements over clicking positions: a name survives a change of window size, position or layout, and a position does not.

### Reading a window

```sh
endia desktop inspect "$m" "$pid" > ui.json
jq -c '.. | objects | select(.controlType?) | {controlType, name, automationId}' ui.json
```

`desktop inspect` prints the window's elements as Windows UI Automation sees them: for each, its control type, name, automation ID, value (never for a password field), whether it is enabled and visible, the patterns it supports (such as `Invoke` and `Value`), and where it is. For the sample's window it shows `Window` "Sample Desktop", `Edit` "Customer name" with the automation ID `CustomerName`, and `Button` "Save".

### Acting on elements

An element is named by a path of segments separated by `/`. **The first segment always names one of the process's windows**, and each later segment is searched for anywhere inside what the segment before it found. A segment gives a control type, a name in square brackets compared exactly, an automation ID after `#`, and a position after `:` counting from 1, in that order; it needs at least one of the first three.

| Selector | Finds |
|---|---|
| `Window[Sample Desktop]/Button[Save]` | the Save button in the window titled `Sample Desktop` |
| `Window/Button[Save]` | the Save button in the process's one window, whatever its title |
| `Window[Sample Desktop]/Edit#CustomerName` | the text box whose automation ID is `CustomerName` |
| `Menu/MenuItem[Exit]` | Exit in a Windows menu the program has opened, which is a window of its own whose control type is `Menu`. A menu drawn by another framework may be a `Window` instead: `Window/MenuItem[Exit]` (see the tray program above). |
| `Button[Save]` | **nothing**: it asks for a window that is a button, and fails with `ELEMENT_NOT_FOUND` |

```sh
endia desktop wait "$m" "$pid" "Window[Sample Desktop]/Edit#CustomerName"              # returns once the box exists
endia desktop set-value "$m" "$pid" "Window[Sample Desktop]/Edit#CustomerName" "Ada"   # prints {"value":"Ada"}
endia desktop invoke "$m" "$pid" "Window[Sample Desktop]/Button[Save]"                  # prints {"invoked":true}
```

`set-value` and `invoke` work through UI Automation, without the mouse, so they work whatever covers the window. A selector that matches nothing, or several elements, is refused with the window's element tree in the error, so the test's log shows what was there.

### Waiting for the screen

A program shows its window a moment after it starts, and a window changes a moment after a click. `desktop wait` reads the window again every half second until the element exists, and prints it; `--gone` waits until it has gone, for example a sign-in form after signing in. `--timeout <seconds>` sets the longest wait (default 60), after which it fails with `TIMEOUT` and the last element tree it read. Use it instead of `sleep` or a loop of your own:

```sh
endia desktop wait --timeout 120 "$m" "$pid" "Window[Sample Desktop]"   # one segment: waits for the window
endia desktop wait --gone "$m" "$pid" "Window[Sign in]"
```

### Passwords

`set-value`, `keys` and the pointer refuse a password field, so that a password is never typed by accident or written to a log. Pass a password on standard input with `--secret-stdin`; EastIndia writes it into the field and never prints, logs or reads it back:

```sh
printf '%s' "$password" | endia desktop set-value --secret-stdin "$m" "$pid" "Window[Sign in]/Edit#Password"
```

### Keyboard

```sh
endia desktop keys "$m" "$pid" "ctrl+a"            # key chords, separated by spaces: "alt+f4 enter"
endia desktop keys --text "$m" "$pid" "Grace"      # types the text as written
```

`keys` brings the process's main window to the front first, then presses the keys wherever its focus is.

### Mouse

```sh
endia desktop pointer "$m" "$pid" click 200,31                  # in the window's client area
endia desktop pointer "$m" "$pid" double-click 200,31
endia desktop pointer --button right "$m" "$pid" click 200,31
endia desktop pointer "$m" "$pid" scroll 200,31 --delta -3      # three notches down
endia desktop pointer --screen "$m" click 838,744               # anywhere on the screen
```

With a process ID, the point is in physical pixels from the top-left corner of the window's client area, the inside of the window below its title bar, and the window is brought to the front first. In the sample, the text box is at 20,20 in the client area and Save at 20,60, so `200,31` lands in the text box and `70,71` on Save. With `--screen`, the point is on the screen, and no window is brought forward. Each pointer action prints the screen point and the window and process it reached.

To click an element, name it instead of working out a point: `desktop click` brings its window to the front and clicks the centre of the element.

```sh
endia desktop click "$m" "$pid" "Window[Sample Desktop]/Button[Save]"
endia desktop click --button right "$m" "$pid" "Window[Sample Desktop]/Edit#CustomerName"
endia desktop click --double "$m" "$pid" "Window/List/ListItem:2"
```

Use `invoke` when the element supports it, because it does not depend on the window being uncovered; use `click` for an element that answers only the mouse.

### Elevation prompts

A program that needs administrator rights makes Windows ask for an administrator's name and password. `endia desktop uac` waits for that prompt and answers it:

```sh
endia desktop uac --program setup.exe --user testadmin --password-stdin "$m" < admin-password.txt
endia desktop uac --program setup.exe --cancel "$m"
```

`--program` is the file name the prompt shows: the program's, or for an installer package the `.msi` file's. The command refuses a prompt for any other program, and types nothing into it. The password of `testadmin` is the one the EastIndia PC's owner chose when the root image was prepared.

Windows normally shows the prompt on a separate secure screen, which no program can read or press. The image must turn that off with this line in its recipe, which the sample's `tools.Endiafile` has:

```dockerfile
RUN reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v PromptOnSecureDesktop /t REG_DWORD /d 0 /f
```

Without it, `desktop uac` fails with `CAPABILITY_MISSING` and says so. `endia inspect <machine>` reports `uacPromptAutomation: true` when the setting is in place.

## Screenshots

```sh
endia desktop screenshot -o evidence/desktop.png "$m"              # the whole screen
endia desktop screenshot --pid "$pid" -o evidence/window.png "$m"  # that process's largest visible window
endia desktop screenshot "$m" > shot.png                           # PNG on standard output
```

The image comes back to your test; nothing is kept on the PC or in the machine. The screen of a machine is 1024 by 768 unless its service asks for another size in the Compose file:

```yaml
services:
  client:
    image: sample/tools:1
    x-eastindia:
      screen: 1920x1080
```

The size takes effect when the machine is created, so change it and run `compose up` again to recreate the machines.

## Collecting evidence and logs

Keep everything a failed run needs to be understood without rerunning it. The sample keeps it in `evidence/<run>`:

| Evidence | Command |
|---|---|
| Files the application wrote | `endia cp "$m:C:/ProgramData/MyApp" evidence/` |
| Windows event log entries | `endia exec "$m" powershell -NoProfile -Command "Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='MyApp'} \| Format-List TimeCreated,Message" > evidence/events.txt` |
| The last 200 entries of the System event log, for later reading | `endia exec "$m" powershell -NoProfile -Command "Get-WinEvent -LogName System -MaxEvents 200 \| Export-Csv C:\Windows\Temp\system.csv -NoTypeInformation"`, then `endia cp "$m:C:/Windows/Temp/system.csv" evidence/` |
| The processes running | `endia process ls "$m"` (process ID, parent, session, user, start time, name) |
| The visible windows | `endia desktop windows "$m"` |
| A window's elements and values | `endia desktop inspect "$m" "$pid"` |
| Screenshots | `endia desktop screenshot -o ...` |
| Processor, memory, disk and network use | `endia stats --no-stream "$m"` |
| The machine's settings, addresses and ports | `endia inspect "$m"` |
| A main process's output | `endia compose -p "$run" logs <service>`, for a service with a `command` |

Collect the evidence before `compose down`: removing a machine deletes its disk.

## Logging in with SSH

Every image runs an OpenSSH server on port 22. To use it from your test, publish the port and give `testuser` your public key:

```yaml
services:
  app:
    image: sample/tools:1
    ports:
      - "12222:22"
```

```sh
ssh-keygen -q -t ed25519 -N "" -f ./id && cp ./id.pub ./authorized_keys
endia exec "$m" cmd /c "mkdir C:\Users\testuser\.ssh"
endia cp ./authorized_keys "$m:C:/Users/testuser/.ssh/"
endia exec "$m" icacls C:\Users\testuser\.ssh\authorized_keys /inheritance:r /grant "testuser:F" /grant "SYSTEM:F"
ssh -i ./id -p 12222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null testuser@host.docker.internal whoami
```

OpenSSH refuses a key file that other accounts may change, hence the `icacls` line. A new machine has new host keys, so the test should not record them. Most tests need no SSH: `exec` and `cp` do the same work without keys.

## Removing everything

```sh
endia compose -p "$run" down -v
endia ps -a        # nothing of the run is left
```

`down` shuts each machine down, removes it with its disk, and removes the fleet's networks; `-v` also removes its named volumes. Images stay, for the next run. `down` gives Windows up to `stopTimeoutSeconds` (120 seconds by default) to shut down, then turns the machine off; `-t <seconds>` changes the wait for one command.

* `endia compose stop` and `start` stop and restart machines while keeping their disks, for a test that needs a restart or a cold boot. `endia restart <machine>` restarts Windows and returns once the machine is ready again, with `testuser` signed in, so the next command needs no wait.
* `endia rmi sample/server:1` removes an image you no longer need; `endia system prune` removes stopped machines and untagged images.
* A run killed before its trap ran leaves its fleet behind; `endia compose ls` lists fleets, and `endia compose -p <name> down -v` removes one.

## The complete sample

`samples/windows-app-testing/run-tests.sh` does all of the above against the three sample programs:

1. publishes the programs for Windows with `dotnet publish -r win-x64`;
2. builds `sample/server:1` from `server.Endiafile`;
3. starts the fleet from `compose.yaml` under a project name of its own, with a trap that removes it;
4. checks the service: Windows reports it running, and the client reaches it by name;
5. drives the desktop program by element, then by keyboard and mouse, and checks the file it saved each time;
6. starts the tray program and checks its process and the file it writes every five seconds;
7. collects the files, event-log entries, process list, screenshots and resource use into `evidence/<run>`.

It needs `endia` with a working context, the .NET 10 SDK, `jq`, `curl`, and a root image tagged `lab/win11:base` on the service, which its `tools.Endiafile` builds on. It prints `PASS: evidence in evidence/<run>`, or `FAIL:` with the check that failed and exits with 1.

## Limits

* **Two machines boot at a time.** A fleet of six takes about three boot times to come up.
* **The PC keeps 12 GiB of memory free.** A machine that would leave less is refused with `CAPACITY_REFUSED`. Each machine's starting memory counts, not the most it may grow to.
* **20 GiB of disk stays free** on the drive that holds the images.
* **`exec` cannot show windows.** It runs as SYSTEM in session 0. Anything that must appear on the screen starts with `desktop launch`.
* **The desktop user is a standard user.** Programs that need administrator rights raise an elevation prompt, which `endia desktop uac` answers in images that set `PromptOnSecureDesktop` to 0.
* **Addresses on the Default Switch change** when the PC restarts. Use names: service names between machines, `host-gateway` for the PC.
* **The evaluation edition ends** 90 days after the root image was prepared, as each image's `eastindia.evaluation.expires` label says. Prepare the root image again from a newer Windows disc before then, and rebuild the images over it.

## When something goes wrong

* `endia operation ls` lists long-running work (builds, imports, `base prepare`, `compose up` and `compose down`, prunes and image-folder moves), and `endia operation logs <id>` shows what it printed.
* `endia compose -p "$run" ps -a` shows every machine, stopped ones included, with its state and health.
* `endia info` lists what needs attention on the service, such as objects whose owner no longer exists.
* A `desktop` command that fails with `DESKTOP_UNAVAILABLE` found no visible window for the process: the program had not yet shown its window, or had closed it. Wait for the window with `desktop windows` and try again.
* A selector that matches nothing fails with `ELEMENT_NOT_FOUND` and the step of the path that failed; one that matches several fails with `ELEMENT_AMBIGUOUS`. Add an automation ID or a `:n` position.
* A selector whose first segment matches none of the process's windows fails, and the tree in the error shows the windows' own elements **without their children**, even when the windows have some. The empty `children` does not mean the window is empty: read it with `desktop inspect`, and correct the first segment, often `Menu` that should be `Window`.
* A password field refuses `keys`, `set-value` and the pointer with `ACTION_UNSUPPORTED`, and `inspect` never shows its value. Enter a password with `set-value --secret-stdin`.
* `ELEMENT_NOT_FOUND` for a selector that does not start with a window, such as `Button[Save]`: start it with the window, `Window/Button[Save]`.
* `CAPABILITY_MISSING` from `desktop tray` or `set-value --secret-stdin`: the machine's image was made from a root image prepared with a EastIndia that did not have them. Prepare the root image again and rebuild the images over it.
