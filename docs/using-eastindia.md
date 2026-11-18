# Using EastIndia

EastIndia gives automated tests real Windows desktops to work in. You describe Windows images in Dockerfile-style recipes and the machines that run them in Compose files. EastIndia then creates the machines, and your tests run programs in them, copy files in and out, drive their desktops and take screenshots. If you know Docker and Docker Compose, you already know most of EastIndia: an image is a Windows disk instead of a container image, and each Compose service becomes a Hyper-V virtual machine instead of a container.

This guide is for people and for AI agents. It covers installing the service, building images, deploying one machine or many, working inside running machines, and two complete walkthroughs.

## How the parts fit together

* **The EastIndia service** runs on the Windows PC that hosts Hyper-V. It does all the work: it creates, starts and removes virtual machines, and talks to the programs inside them.
* **The `endia` command line** is how you ask the service for work. It runs on the PC itself or in a Docker sandbox on the same PC, and it follows Docker's commands and options wherever Docker has one.
* **The desktop app**, East India, shows the fleets, machines, images and operations, as Docker Desktop shows containers. It lives in the notification area beside the clock: clicking or double-clicking its icon shows the window, and closing the window in any way (its Close button, Alt+F4 or the taskbar's Close window) hides it again and leaves the app running there. Only **Quit East India** in the icon's menu ends it.
* **Access** follows Docker Desktop. On the PC, members of the `eastindia-users` group reach the service through a named pipe and need no certificate. A Docker sandbox presents a client certificate instead. Anyone the service lets in may run every command.
* **An image** is a Windows disk that machines start from. A root image is Windows with EastIndia's programs, which `endia base prepare` installs from a Windows disc; a built image adds the steps of a recipe on top of a parent image.
* **A machine** is a Hyper-V virtual machine on its own new disk, layered over an image. A machine that is removed takes its disk with it; the image is unchanged.
* **A fleet** is everything one Compose project creates: its machines, private networks and volumes. `endia compose up` creates it and `endia compose down` removes it.

| Docker | EastIndia |
|---|---|
| `docker build` | `endia build`, with a recipe in Dockerfile syntax |
| `docker compose up`, `down`, `exec`, `cp`, `logs` | the same commands under `endia compose` |
| a container | a machine |
| a container's main process | a machine's main process; when it exits, the machine stops |
| `docker exec`, `docker cp`, `docker top` | `endia exec`, `endia cp`, `endia process ls` |
| (none) | `endia desktop`, which drives a machine's Windows desktop |

EastIndia has no `endia run`. Machines come only from a Compose file, even when you need just one.

## Installing EastIndia

EastIndia installs from an MSI, as Docker Desktop installs from its own installer. Hyper-V must be enabled, and Windows must be Windows 11 Pro or Enterprise, x64, build 26100 or later.

Each release on this repository's [Releases page](https://github.com/teaToolkit/EastIndia/releases) has three MSIs:

| MSI | What it installs |
|---|---|
| `EastIndiaDesktop-<version>.msi` | The service, the command line `endia.exe` and the desktop app. Choose this for a developer's PC. |
| `EastIndiaService-<version>.msi` | The service and the command line, without the desktop app. |
| `EastIndiaCLI-<version>.msi` | The command line on its own. |

East India Desktop and East India Service each replace the other, because a PC runs one EastIndia service. East India CLI installs beside either. The steps below install East India Desktop; the others install the same way.

1. **Download the MSI** from the [Releases page](https://github.com/teaToolkit/EastIndia/releases). The MSI and the programs in it carry one version, which `endia --version` prints. It is `major.minor.patch`, and a later version always replaces an earlier one.

2. **Install it**, naming the image folder, which holds EastIndia's Windows discs, disks and virtual machines:

   ```
   msiexec /i EastIndiaDesktop-<version>.msi IMAGEFOLDER=M:\eastindia
   ```

   Windows asks for administrator rights. Opened this way, or by double-clicking the file, the MSI shows its progress and then a window that says whether the installation succeeded, failed or was cancelled. Without `IMAGEFOLDER`, the image folder stays as already configured, or is `C:\ProgramData\EastIndia\image-folder` on a first installation. winget passes the same setting with `--custom "IMAGEFOLDER=M:\eastindia"`.

3. **Sign out and in again.** The installer adds you to the `eastindia-users` group, and Windows reads an account's groups only when it signs in.

4. **Check it.** `endia version` prints the versions of both the command line and the service.

The installer does four things:

* It copies the programs to `C:\Program Files\EastIndia`, one folder per program, and puts `endia` on the system path. The command was called `eindia` until 10 November 2026; `eindia` still works as an alias of `endia` in this release and the next, so that existing scripts keep running, and is then removed.
* It gives the programs the .NET 10 they run on. The programs are published without .NET, so the MSI holds only EastIndia's own files. Each program looks for .NET first in `C:\Program Files\EastIndia\dotnet`, then in the .NET installed in Windows. The installer downloads from Microsoft what is missing:
  * When `C:\Program Files\EastIndia\dotnet` exists, it adds any framework that folder lacks.
  * Otherwise, when the .NET installed in Windows has every framework, it downloads nothing.
  * Otherwise it downloads every framework into `C:\Program Files\EastIndia\dotnet`.

  It checks each download against the hash in Microsoft's release list. A download needs internet access; without it, the installation fails and is rolled back. The client needs only .NET itself. The server also needs ASP.NET Core and the Windows Desktop framework. The guest programs use the Windows Desktop framework: `endia base prepare` copies the server's .NET into each new Windows for them.
* It prepares the PC, as a Linux package's post-install script does. It creates the `eastindia-users` group and adds you to it. It sets the image folder. To change it later, run the MSI again with `IMAGEFOLDER` set to the new folder: the setup step then uses that folder in place of the configured one. It gives the local `eastindia` account, which EastIndia signs in to Hyper-V as, access to Hyper-V. It creates EastIndia's certificate authority. Each step changes only what differs, and every upgrade repeats them. It writes what it did to `C:\ProgramData\EastIndia\install.log`.
* It installs and starts the Windows service `TeaToolkit.EastIndia`. The service starts with Windows, and Windows restarts it 60 seconds after a failure.

**Updating** is installing a newer MSI. It stops and removes the installed service and programs, installs the new ones, prepares the PC again and starts the service, and it keeps your images, records, certificates and the downloaded .NET. An older MSI refuses to install over a newer one.

**Uninstalling**, from Settings > Apps or with `msiexec /x EastIndiaDesktop-<version>.msi`, removes the programs, the service and the downloaded .NET. The downloaded .NET stays while East India CLI is still installed. Uninstalling leaves `C:\ProgramData\EastIndia`, the image folder, the `eastindia-users` group and EastIndia's Hyper-V account.

A Windows service named `TeaToolkit.EastIndia` that was created by hand stops the MSI from installing its own. Remove it first, in an administrator prompt, with `sc.exe stop TeaToolkit.EastIndia` and then `sc.exe delete TeaToolkit.EastIndia`.

**Configuration** follows Docker's `daemon.json`. The settings are in `C:\ProgramData\EastIndia\config\policy.json`, which you edit in an administrator editor. The service reads the file when it starts, so restart it afterwards with `sc.exe stop TeaToolkit.EastIndia` and then `sc.exe start TeaToolkit.EastIndia`. One key is the exception: `stateRefreshMilliseconds`, 250 to 60000 with 1000 as its default, takes effect without a restart. It is how often the service reads the machines, the fleets and Hyper-V's power states into the one snapshot that `endia ps`, `endia compose ps`, `endia compose ls`, `endia inspect` and `endia info` answer from. A change you make yourself shows at once; a machine that stops by itself can take up to one interval to show. A key the service does not know, or a value out of range, stops it from starting, and the service log names the key. `endia info` prints every setting in effect, and the desktop app's Settings page lists the main ones under Service, with **Open settings file**. Its **Refresh interval**, in seconds from 0.25 to 60, changes `stateRefreshMilliseconds` with **Apply**, which works only in the app on the PC itself, not from a sandbox.

## Who may use the service

EastIndia follows Docker Desktop:

* **On the PC, the `eastindia-users` group.** The service listens on the named pipe `\\.\pipe\eastindia_engine`, a channel that only programs on the same PC can open. Windows checks the account when `endia` opens the pipe, and lets in members of `eastindia-users` and administrators, so no certificate is needed. Docker Desktop does the same with `\\.\pipe\docker_engine` and `docker-users`. To let in another person, run `net localgroup eastindia-users <account> /add` in an administrator prompt; that person then signs out and in again.
* **From a sandbox, a client certificate.** A sandbox cannot open the PC's named pipe, so it connects over HTTPS, and the service checks its certificate when the connection opens.

## Connecting from a Docker sandbox

The service's HTTPS address is the PC's own loopback address, `127.0.0.1:7443`. A sandbox cannot use that address, because inside the sandbox it means the sandbox itself. Instead, the sandbox's proxy forwards `host.docker.internal` to the PC's loopback address for each port that the sandbox's policy allows. It passes the encrypted connection through untouched.

1. **Allow the port**, once per sandbox, on the PC. `sbx` is the Docker Sandboxes command that runs on the PC; `<sandbox>` is the sandbox's name, which `hostname` prints inside it:

   ```
   sbx policy allow network --sandbox <sandbox> localhost:7443
   ```

2. **Export a context for the sandbox**, on the PC:

   ```
   endia context export sandbox-1
   ```

   The service issues a new client certificate named `sandbox-1`, valid for 365 days. After that the service refuses the certificate, so the sandbox must be given a new one: revoke the old one (`endia cert rm sandbox-1`), then run `endia context export` again. The command writes `sandbox-1.eastindiacontext`, which holds the address the sandbox connects to and the certificate files, in the layout that `docker context export` uses. The file holds the certificate's private key unencrypted, so only you may read it. The service issues certificates only to callers on the named pipe, so a sandbox cannot give itself more. `--eastindia-host` changes the address, which is `tcp://host.docker.internal:7443` by default.

3. **Copy the file into the sandbox as a file.** Do not store it as a sandbox secret (`sbx secret`). The proxy then opens the encrypted connection itself, and the service never sees the client certificate.

4. **Get the Linux command line.** The MSI holds only the Windows command line. Download `endia-linux-x64` from the [Releases page](https://github.com/teaToolkit/EastIndia/releases), make it executable with `chmod +x endia-linux-x64`, and put it on the sandbox's `PATH` as `endia`.

5. **Import the context and use it**, in the sandbox, then delete the file:

   ```
   endia context import pc sandbox-1.eastindiacontext
   endia context use pc
   endia version
   ```

   `endia version` prints the versions of both the command line and the service. When the service refuses the certificate or cannot be reached, the command exits with 1 and names the cause.

On the PC, `endia cert rm sandbox-1` ends the certificate at once and closes its open connections, and `endia cert ls` lists every certificate with its state. Both work only on the PC, through the named pipe, so a sandbox cannot list or end another's access.

Instead of a context, two environment variables can name the address and a folder that holds `ca.pem`, `cert.pem` and `key.pem`, as `DOCKER_HOST` and `DOCKER_CERT_PATH` do: `EASTINDIA_HOST=tcp://host.docker.internal:7443` and `EASTINDIA_CERT_PATH=<folder>`.

## Building and layering images

Images form layers. A root image holds Windows and EastIndia's own programs. Each built image adds the steps of a recipe on top of its parent and is stored as a disk of differences over the parent's disk. Every parent becomes read-only, so one Windows disk serves every image built on it. Building a new application layer therefore does not repeat the slow steps below it.

### The root image: Windows itself

Every image starts from a Windows disk that holds EastIndia's own programs. `endia base prepare` makes one from a Windows installation disc:

```
echo "$PASSWORD" | endia base prepare M:\eastindia\windows11-iot-ltsc-2024-eval-x64.iso --tag lab/win11:base --password-stdin
```

Set `PASSWORD` in your shell to the password you choose, and make it meet Windows' own password rules, because Windows Setup applies them. The ISO must be in the image folder, `M:\eastindia`, because the `eastindia` account on the PC may read files only there. The password is for both accounts the new Windows has: `testuser`, a standard account that signs in automatically at every start, and `testadmin`, an administrator whose name and password answer an elevation prompt. `--desktop-user` and `--admin-user` change the names, and `--index` chooses another edition on the disc. The service keeps the password in memory only. It reaches nothing but the answer file, the list of settings Windows Setup follows, which is deleted once Windows is installed.

The command takes about half an hour. It installs Windows in a machine of its own, without anyone at the screen, together with:

* EastIndia's guest service, through which the service on the PC reaches every machine;
* EastIndia's desktop helper, started at every sign-in, which works the screen, keyboard and pointer for the desktop commands;
* an OpenSSH server.

It then reads which edition and build it installed, and when an evaluation copy expires, and turns Windows Update off. Every machine is short-lived, so updating Windows would only spend the machine's processor time, memory and network on work that is thrown away with it. Microsoft Defender still looks for its own updates, and its downloads fail. If any Windows Update setting cannot be made, the command fails with `CAPABILITY_MISSING` and the error, and keeps no image. Last, it imports the disk as a base, which boots it once more to check, in order:

1. `guest-service`: the guest service answers;
2. `fast-startup`: Fast Startup is off, so that stopping and starting a machine boots Windows afresh;
3. `desktop`: the desktop account is signed in with the desktop helper running;
4. `ssh`: SSH answers on port 22;
5. `evaluation`: Windows says when its evaluation period ends, or that it is not an evaluation copy;
6. `shutdown`: Windows shuts down cleanly.

A failed check fails the command with `CAPABILITY_MISSING` and names the check that failed, using the name that starts its line in the list above, such as `ssh`. When every check passes, the command's last line is the new image's digest, as `docker import` ends by printing the new image's ID. Removing the base later deletes its disk.

**A disk you prepared yourself** can be imported instead, if it is a stand-alone VHDX with the guest service installed as the Windows service `EastIndiaGuest`, the desktop helper started at sign-in, automatic sign-in of a desktop account, an OpenSSH server, and Fast Startup off (`HiberbootEnabled` set to 0 under `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power`). Import it as `docker import` imports a file:

```
endia import M:\eastindia\win11.vhdx lab/win11:base
```

The import copies the disk into the image folder (`--move` moves it instead), makes it read-only and runs the same import check, then prints the new image's digest. The copy needs the disk's size plus the 20 GiB that EastIndia keeps free on the image folder's drive (`minFreeDiskGiB`); with less free, the import fails with `STORAGE_FULL` and copies nothing. A disk attached to a virtual machine, or one that is already an image's disk (the same file, or a copy that carries the same Hyper-V disk identifier), is refused with `RESOURCE_IN_USE`, naming the virtual machine or the image. Every machine made from the image waits for the account that the `desktop` check found signed in. The `evaluation` check records when an evaluation copy expires, so that `endia images` warns before it does. `-c` (`--change`) sets the image's configuration with a recipe instruction, as `docker import --change` does: `LABEL`, `ENV`, `WORKDIR`, `CMD`, `ENTRYPOINT` or `EXPOSE`, for example `-c "ENV LANG=en-GB"`.

### Built images: software and settings on top

A recipe adds software and Windows settings to a parent image, in Dockerfile syntax. Its file is an Endiafile: `Endiafile` when a folder holds one recipe, or `name.Endiafile`, such as `tools.Endiafile`, when it holds several. EastIndia also reads Docker's names: `endia build` without `-f` reads `Endiafile`, or `Dockerfile` when there is no `Endiafile`, and `-f` takes a file of any name, so an existing `app.Dockerfile` still builds. As with a Docker image, the recipe installs everything the test needs, .NET included: the root image holds only Windows and EastIndia's own programs. A typical stack has two built layers: one with the runtime every test needs, and one with the application under test.

In these recipes `SHELL` names `powershell.exe`, which is Windows PowerShell 5.1, the version that ships with Windows.

```dockerfile
# tools.Endiafile: .NET 10 and its desktop runtime, over Windows
# escape=`
FROM lab/win11:base
SHELL ["powershell.exe", "-NoProfile", "-Command"]
WORKDIR C:\setup
COPY dotnet-install.ps1 .
RUN .\dotnet-install.ps1 -Channel 10.0 -Runtime dotnet -InstallDir 'C:\Program Files\dotnet'
RUN .\dotnet-install.ps1 -Channel 10.0 -Runtime windowsdesktop -InstallDir 'C:\Program Files\dotnet'
RUN [Environment]::SetEnvironmentVariable('Path', $env:Path + ';C:\Program Files\dotnet', 'Machine')
```

`dotnet-install.ps1` is Microsoft's install script, from `https://dot.net/v1/dotnet-install.ps1`, kept in the build context. The desktop runtime needs the base runtime, which brings `dotnet.exe`, so the base runtime is installed first.

```dockerfile
# app.Endiafile: the application and the Windows settings it needs, over the tools
# escape=`
FROM lab/tools:1
SHELL ["powershell.exe", "-NoProfile", "-Command"]
COPY app/ C:/app/
RUN netsh advfirewall firewall add rule name=OrderService dir=in action=allow protocol=TCP localport=8080
RUN Add-Content C:\Windows\System32\drivers\etc\hosts "10.0.0.50 licence-server.lab"
RUN reg add HKLM\SOFTWARE\Contoso\Orders /v Mode /t REG_SZ /d Test /f
```

```
endia build -t lab/tools:1 -f tools.Endiafile .
endia build -t lab/app:dev -f app.Endiafile .
```

**Tip: highlighting in VS Code.** VS Code recognises `Dockerfile` by name but not `Endiafile`. To give Endiafiles Dockerfile highlighting, add this to your settings (File › Preferences › Settings, then the Open Settings (JSON) button):

```json
"files.associations": {
  "Endiafile": "dockerfile",
  "*.Endiafile": "dockerfile"
}
```

As with `docker build`, the final argument is the build context: the folder whose files `COPY` can use. The command line sends it with the request as a tar archive, leaving out what the ignore file lists. The ignore file is the first of these that exists: `<recipe>.endiaignore` beside the recipe, such as `app.Endiafile.endiaignore`; `<recipe>.dockerignore` beside the recipe; `.endiaignore` at the root of the context; and `.dockerignore` at the root. Only that one file applies; its patterns follow Docker's `.dockerignore` rules. The recipe may lie outside the context; it is sent with it. A symbolic link travels as a link, and a `COPY` that would copy one fails.

The command prints what Docker's classic builder prints: `Step 4/6 : COPY dotnet-install.ps1 .` before each instruction, the output of each `RUN` as it is written, then `Successfully built` with the image's short ID and `Successfully tagged` for each tag. A stage that matches an earlier build prints its `FROM` step and then `Using cache:` with the short ID of the earlier result, instead of its other steps. A `--build-arg` that no `ARG` declares is ignored, with Docker's warning `[Warning] One or more build-args [<names>] were not consumed`.

* **Instructions.** A recipe may use `FROM`, `ARG`, `SHELL`, `RUN`, `COPY`, `WORKDIR`, `ENV`, `LABEL`, `USER`, `EXPOSE`, `ENTRYPOINT` and `CMD`, with one or more `FROM` lines, each beginning a stage (below). `RUN`, `CMD` and `ENTRYPOINT` take the JSON form or the shell form, and the shell form runs through `cmd /S /C` unless `SHELL` changes it. As in Docker on Windows, the shell receives the command exactly as written, after its own words, so the shell reads the quotes in the command itself. A shell-form `ENTRYPOINT` ignores `CMD`, including the `CMD` of an image built on it and a Compose `command`. Options on `COPY` and `RUN`, here-documents, a UDP port in `EXPOSE`, and the instructions `ADD`, `VOLUME`, `HEALTHCHECK`, `ONBUILD`, `STOPSIGNAL` and `MAINTAINER` are refused with `UNSUPPORTED_FIELD`, naming the line and column. A recipe that breaks the Dockerfile rules, such as an unknown instruction or an instruction other than `ARG` before `FROM`, is refused with `INVALID_DEFINITION` in the same form.
* **Account.** A `RUN` step runs as SYSTEM, unless a `USER` instruction names another account; the step then runs as that account.
* **The hosts file.** Entries a recipe adds to the hosts file stay. EastIndia writes its own entries only between the lines `# eastindia begin` and `# eastindia end`, and leaves every other line alone. Its entries are the names of a fleet's machines and the service's `extra_hosts`.
* **Restarts.** A `RUN` step that exits with 3010 makes the builder restart the machine and carry on. A step that exits with 1641 has started a restart itself, and the builder waits for it. Any other non-zero exit fails the build and quotes the step's last 50 lines of output.
* **Time.** Each `RUN` step may take up to 30 minutes.
* **Reuse.** Building the same stage again with the same inputs reuses its earlier result, as Docker's cache does, but one stage at a time rather than one instruction at a time. "Layers, stages and the build cache" below explains what that means for how you write a recipe. `--no-cache` builds every stage again.
* **Tags and labels.** `-t` may be given several times, and every tag names the new image; without `-t` only its digest does. `--label tier=test` adds a label, replacing a recipe `LABEL` of the same name. `-q` prints only the new image's digest.
* **Size.** A build machine has 2 GiB of memory and 2 processors. `-m 4g` and `--cpus 4` change them; less than 2 GiB is refused. Build machines can reach the internet, so recipes can download installers.

`endia images` lists the images with the options of `docker images`: `-q`, `--digests`, `--no-trunc`, `-a`, and `-f` with `dangling=true`, `label=<key>[=<value>]` or `reference=<pattern>`. Given a name, as in `endia images lab/tools`, it lists only the tags of that name; given a pattern, as in `endia images "lab/*:1"`, only the tags that match it. `image inspect` prints a JSON array with one record per image, as Docker does: its ID (`id`), tags (`repoTags`), parent (`parentId`), creation time (`created`), configuration (`config`), labels (`labels`) and the machines made from it (`machines`). `tag` points a tag at an image and `rmi` removes tags and images. Each takes the arguments of its Docker counterpart. An image is named, as in Docker, by a tag, by its digest, or by its ID. A digest may follow a name, as in `lab/tools@sha256:<digits>`; the digest alone then decides the image. An ID is any start of the digest's hexadecimal digits that no other image's digest shares, such as the 12 digits in the `IMAGE ID` column. When several images share the digits given, the command fails with `NOT_FOUND` and asks for more digits. A tag spelt the same as an ID names the tagged image, as in Docker. A name whose first part names a registry, such as `registry.local/lab/app`, `registry:5000/app` or `localhost/app`, is refused with `UNSUPPORTED_FIELD`, because EastIndia has no registry. `rmi` never deletes an image that another image or a stage in the build cache is built on, or that a machine was made from, even with `--force`: the disk of that other image, stage or machine is a differencing disk over the image's disk. `endia builder prune` deletes the stages that nothing else uses, which frees such an image.


### Layers, stages and the build cache

**One layer per stage.** Docker caches every instruction, so a change to one `COPY` reruns only the steps from that line on. EastIndia cannot do that cheaply. Each layer is a Windows disk of differences, and the builder makes one by shutting Windows down and keeping its disk. A layer per instruction would cost a shutdown, a start and one more disk for every line of the recipe. EastIndia therefore makes one layer for each stage of a recipe. A recipe with one `FROM` is one stage, so any change, however small, rebuilds all of it. You decide where the layers fall by splitting the recipe into stages.

**Where to put the boundaries.** Put slow steps that rarely change in an early stage, such as installing Visual Studio or a runtime. Put the steps that change often in a later stage built `FROM` it, above all copying in the application under test. A change then rebuilds only the stage that holds it, and every stage after it. Add a stage only where a rebuild would otherwise repeat slow work. Each stage costs a Windows shutdown and start, and adds one disk to the image's chain, which `maxLayerDepth` limits to 8 parents.

This Endiafile makes a build machine in three stages:

```dockerfile
# escape=`
FROM lab/win11:base AS builder-dotnet
SHELL ["powershell.exe", "-NoProfile", "-Command"]
COPY dotnet-install.ps1 C:/setup/
RUN C:\setup\dotnet-install.ps1 -Channel 10.0 -InstallDir 'C:\Program Files\dotnet'

FROM builder-dotnet AS builder-cpp
RUN <install the Visual Studio Build Tools>

FROM builder-cpp AS builder
RUN <install the last, smallest tools>
```

`FROM builder-dotnet` names the stage above it, so `builder-cpp` starts from that stage's result, with its settings. A stage name is lower case: letters, digits, `.`, `_` and `-`, starting with a letter.

**Choosing and naming stages.** A build makes the last stage unless `--target` names another, as in Docker. Only the target and the stages it is built on are built. To give each stage its own name, build it with `--target` and `-t`:

```
endia build --target builder-dotnet -t vgs/builder-dotnet:1 .
endia build --target builder-cpp -t vgs/builder-cpp:1 .
endia build -t vgs/builder:1 .
```

The second build finds `builder-dotnet` in the cache and builds only `builder-cpp`, and the third builds only `builder`. A stage found in the cache prints its `FROM` step and then `Using cache:` with the short ID it reused. If a later stage fails, the stages before it stay in the cache, so the next attempt starts from the last one that succeeded. `COPY --from`, which copies files out of another stage, is not supported.

**The build cache.** A stage below the target that no tag names is kept as build cache, not as an image. `endia images` never lists it, even with `-a`, so it never appears as `<none>`. `tag`, `rmi`, `image inspect` and `FROM` do not accept it either, although an image's `parentId` and `chain` may name it, because its disk lies under the image's own. When you later build that stage as a target, the cached result becomes an image. After each build, EastIndia deletes cache that nothing uses, oldest first, once the cache takes more than 20 GiB (`buildCacheKeepGiB`). A cache entry stays while an image, a machine or another cache entry is built on it. `endia system df` shows the cache on its own `Build Cache` line.

**Clearing up.** `endia builder prune` deletes all the cache that nothing uses, after Docker's warning; `-f` skips the question. `endia system prune` deletes it too, with `- unused build cache` in its warning. `rmi` refuses an image that a cache entry is built on and names `endia builder prune`, which frees it.

**Where `<none>` still comes from.** Two things still leave images without a name, as they do in Docker. A build without `-t` makes an image that only its digest names. A rebuild under the same tag moves the tag to the new image, and the old one is left untagged, which Docker calls dangling. `endia system prune` deletes such images, together with any untagged images they were built on.

**In the desktop app.** Images › Build an image… opens a dialog over the whole window. Blueprint is the recipe file. Materials is the folder whose files `COPY` can use, filled in from the blueprint's folder. Name is the tag, and may be left empty. Output shows the image folder, where every image is kept; it cannot be changed there, and its i says to move the image folder in Settings › Storage › Image folder instead. "Rebuild, ignoring the cache" is `--no-cache`. The app always builds the whole blueprint, so naming a single stage needs the command line. Copy as CLI gives the matching `endia build` command. The Prune dialog lists the build cache as one row and deletes it with the rest.

## Deploying a single machine

A Compose file with one service describes one machine:

```yaml
name: orders-dev
services:
  dev:
    image: lab/app:dev
    ports:
      - "18080:8080"
```

```
endia compose up --wait
```

The machine is named `<project>-<service>-<n>`, here `orders-dev-dev-1`. `up --wait` returns once the machine is running and ready. Ready means that its virtual machine runs, its configuration was applied in this boot, and nothing has failed since. When the image has a desktop account, that account must also be signed in, with the desktop helper running. A machine with a health check must also be healthy.

A service with no `entrypoint` or `command`, in the Compose file or in its image, has no main process, and its machine keeps running until you stop it. That suits a machine you work in for hours. A service with a main process behaves like a container: when the program exits, the machine shuts down, and `restart:` decides whether it starts again.

| To | Run |
|---|---|
| see the machine and its state | `endia compose ps` or `endia ps` |
| stop it, keeping its disk | `endia compose stop` |
| start it again | `endia compose start` |
| restart Windows in it | `endia restart orders-dev-dev-1` |
| remove it and its disk | `endia compose down` |

**Memory and processors.** A machine starts with 2 GiB of memory, or with its `mem_limit` when that is smaller. Windows gives memory back while it is idle, down to 512 MiB, and receives more when it needs it, up to `mem_limit`, or up to 4 GiB when the service sets none. A `mem_limit` below 2 GiB is refused, because Windows needs at least that much. `cpus` sets the number of processors, rounded up; a fraction also caps their use. The default is 2.

**Published ports.** A published port listens on the PC's `127.0.0.1` only, and EastIndia joins each connection to `127.0.0.1:<target>` inside the machine. In the example, a program on the PC reaches the machine's port 8080 at `127.0.0.1:18080`. From a sandbox, connect to `host.docker.internal:18080` after allowing `localhost:18080` in the sandbox's policy, as "Connecting from a Docker sandbox" does for port 7443. A port given without a published number gets a free one between 49152 and 65535, which can change when the machine restarts; `endia inspect <machine>` lists each port's `published` number.

## Deploying many machines

The same Compose file format describes a fleet of machines that work together:

```yaml
name: orders-test
services:
  server:
    image: lab/app:dev
    command: ["C:\\app\\OrderService.exe"]
    healthcheck:
      test: ["CMD", "curl.exe", "-fs", "http://127.0.0.1:8080/health"]
      interval: 5s
    networks: [lab]
  client:
    image: lab/app:dev
    deploy:
      replicas: 3
    depends_on:
      server:
        condition: service_healthy
    networks: [lab]
networks:
  lab: {}
```

`endia compose up --wait` creates one server and three clients: `orders-test-server-1` and `orders-test-client-1` to `-3`. It starts the server first and waits until its health check passes, because the clients depend on it being healthy. `--scale client=5` changes the number of clients for one run.

* **Names.** Machines on the same network reach each other by service name: each client reaches the server at `server`. EastIndia writes the names into every machine's hosts file, because it runs no DNS server.
* **Networks.** Each network in the file is a private Hyper-V switch with its own address range, taken from the configured `defaultAddressPools`. By default these are the range `10.231.0.0/16`, cut into `/24` subnets, one subnet per network. Every machine also has a card on the PC's `Default Switch`, which reaches the internet and the PC, unless all its networks are marked `internal: true`.
* **Boots.** At most two machines boot at the same time; the others wait their turn. A fleet of six takes about three boot times to come up.
* **Volumes.** A named volume is a separate disk that keeps its data until `endia compose down -v`. It belongs to one machine.
* **Replicas.** Commands that act on one replica take `--index`, for example `endia compose exec --index 2 client ...`.

`depends_on` also accepts `service_started` and `service_completed_successfully`. `environment`, `env_file`, `hostname`, `container_name`, `user`, `working_dir`, `entrypoint`, `labels`, `extra_hosts`, `restart`, `expose`, `scale`, `cpus`, `mem_limit`, `stop_grace_period`, `platform` and `develop.watch` are also accepted, and so are `image`, `build`, `command`, `healthcheck`, `ports`, `volumes`, `depends_on`, `deploy` and `networks`. `deploy` takes only `replicas` and `resources.limits`, and `x-eastindia` takes `screen`. Any other key is refused with `UNSUPPORTED_FIELD`, naming it, so a typing mistake never passes silently. `endia compose config` shows the file as EastIndia reads it.

**Launching again over a running fleet.** Running `endia compose up` again for a fleet that is already up brings it to what the file now says. By default it recreates only a machine whose service or image changed, keeps every other machine as it is, and leaves alone a machine whose service is no longer in the file, as Docker Compose does. Recreating a machine removes it with its disk and creates it again from its image. These options change that, and matter mostly when the fleet is already up:

| To | Run | When it matters |
|---|---|---|
| launch only some services | `endia compose up web db` | when you want part of a fleet, or are working on one service; the services they depend on come up too |
| replace every machine | `endia compose up --force-recreate` | when you want fresh machines from their images, even though nothing in the file changed |
| keep existing machines, even changed ones | `endia compose up --no-recreate` | when a machine holds work you have not saved elsewhere and a changed service would otherwise replace it |
| remove machines of services no longer in the file | `endia compose up --remove-orphans` | after you rename or delete a service, so that its old machines do not keep running |

The desktop app's Launch a fleet always uses the defaults: every service, machines recreated only when changed, and no machine removed for a service the file no longer has. Use the CLI or the API (`services`, `recreate` and `removeOrphans` of the request) to choose otherwise.

## Deploying and removing software in a running machine

`endia cp` copies files into a running machine, and `endia exec` runs programs in it. Together they install, update and remove software without rebuilding an image:

```sh
endia cp ./publish/. orders-dev-dev-1:C:/app            # copy the folder's contents into C:\app
endia exec orders-dev-dev-1 msiexec /i C:\app\Orders.msi /quiet
endia exec orders-dev-dev-1 msiexec /x C:\app\Orders.msi /quiet
endia exec orders-dev-dev-1 cmd /c rmdir /s /q C:\app
```

* **Copying.** `cp` follows Docker's rules for where a copy lands. A source path ending in `/.` copies a folder's contents; without it, the folder itself is copied into the destination folder. Copying replaces files of the same name and leaves other files in place. The destination folder must already exist, as in Docker, so create it first with `exec`, for example `endia exec <machine> cmd /c "mkdir C:\app"`. `cp` works in both directions: `endia cp orders-dev-dev-1:C:/results ./results` fetches files.
* **Running.** `exec` waits for the program and exits with its exit code: the full code on Windows, that code modulo 256 on Linux. 127 means the program was not found, and 126 that it could not start. Programs run as `SYSTEM`, outside the desktop session. `-u`, `-w` and `-e` set the account, the working folder and the environment. `exec -d` returns at once and prints the program's real Windows process ID; `endia process wait <machine> <pid>` then waits until the program ends and prints its exit code. Windows receives the program and its arguments as one command line. To build it, EastIndia puts double quotes around each argument that is empty or contains a space, tab, line break or `"`. It follows the rules of `CommandLineToArgvW`, which Windows programs use to split their command line. Inside the quotes, a `"` becomes `\"`. Backslashes before a `"`, or at the end of the argument, are doubled: `C:\My Folder\` arrives as `"C:\My Folder\\"`, and the program reads it back as `C:\My Folder\`. Every other backslash, and every argument without those characters, passes unchanged. A PowerShell command run with `-Command` exits with the code of its last statement, so add `-ErrorAction Stop` to a command that must fail the `exec` when it fails, for example `endia exec <machine> powershell -NoProfile -Command "Get-Content C:\app\version.txt -ErrorAction Stop"`.
* **Stopping a program.** `endia process stop <machine> <pid>` asks the program to close and ends it after 10 seconds (`-t` changes the wait).
* **Bind mounts.** A Compose bind mount such as `./fixtures:C:/fixtures` copies a folder into the machine each time `endia compose up` creates, starts or keeps the machine. The copy deletes files that the source no longer has. Changes made inside the machine never come back.

## Seeing what runs in a machine

**Processes.** `endia process ls <machine>` lists every process, as `docker top` does: its process ID, parent, session, account, start time and program name. Session 0 holds services; the desktop user's session holds what runs on the screen.

**Windows.** `endia desktop windows <machine>` lists every visible window on the desktop, frontmost first: the process ID and program name that own it, its handle, its position and size in pixels from the top-left corner of the screen, and its title. `--format json` gives the same list as JSON, one window per line. `endia process inspect <machine> <pid>` shows one process in full, including its hidden windows.

```
$ endia desktop windows orders-dev-dev-1
PID    NAME       HANDLE     POSITION   SIZE       TITLE
4120   Orders     0x2a0b4c   100,50     800x600    Orders
```

**Inside a window.** `endia desktop inspect <machine> <pid>` prints the window's user-interface tree, as Windows UI Automation sees it, in JSON: each button, text box and menu with its control type, name, automation ID and position within the window.

**Services.** EastIndia has no command of its own for Windows services; use Windows' tools through `exec`:

```sh
endia exec orders-dev-dev-1 sc query state= all
endia exec orders-dev-dev-1 powershell -NoProfile -Command "Get-Service | Where-Object Status -eq Running"
```

## Controlling the desktop

The `endia desktop` commands act in the signed-in user's session, where the screen is. Most commands name a process by its ID, and the keyboard and pointer commands first bring that process's main window to the front. `desktop pointer --screen` instead acts at a point on the screen, without naming a process.

The examples read a value from JSON with `jq`, which is a separate program that must be installed on the Linux side where the examples run.

```sh
pid=$(endia desktop launch orders-dev-dev-1 C:\\app\\Orders.exe | jq -r .processId)
endia desktop wait orders-dev-dev-1 "$pid" "Window[Orders]/Edit#CustomerName"
endia desktop set-value orders-dev-dev-1 "$pid" "Window[Orders]/Edit#CustomerName" "Ada"
endia desktop invoke orders-dev-dev-1 "$pid" "Window[Orders]/Button[Save]"
endia desktop click --button right orders-dev-dev-1 "$pid" "Window[Orders]/List/ListItem:3"
endia desktop keys orders-dev-dev-1 "$pid" "ctrl+s"
endia desktop keys --text orders-dev-dev-1 "$pid" "Order 42"
endia desktop pointer orders-dev-dev-1 "$pid" click 120,45
endia desktop pointer --screen orders-dev-dev-1 double-click 960,540
```

| Command | What it does |
|---|---|
| `desktop launch <machine> <program> [args]` | Starts a program on the desktop and prints, in JSON, its process ID (`processId`), start time, session, account, integrity level and windows. |
| `desktop wait <machine> <pid> <element>` | Waits until the element exists, then prints it and its window. With `--gone`, waits until it no longer exists. `--timeout <seconds>` sets the longest wait; the default is the service's `desktopActionTimeoutSeconds`, 60 seconds unless changed. |
| `desktop invoke <machine> <pid> <element>` | Presses a button or other element through UI Automation, without moving the pointer. |
| `desktop click <machine> <pid> <element>` | Brings the element's window to the front and clicks the centre of the element with the pointer, for an element that answers only the mouse. `--button right` and `--double` change the click. |
| `desktop set-value <machine> <pid> <element> <value>` | Sets a text box or similar element, and prints the value read back. A password field accepts only `--secret-stdin`, which reads the value from standard input and never prints or logs it. |
| `desktop keys <machine> <pid> "<chords>"` | Presses key chords such as `"ctrl+s"` or `"alt+f4 enter"`. With `--text`, types the text as written. |
| `desktop pointer <machine> <pid> <action> <x,y>` | Moves the pointer to a point in the process's main window and clicks, double-clicks or scrolls there. `--button right` and `--button middle` change the button; `--delta -3` scrolls three notches down. It prints the screen point, and the window there with the process that owns it. |
| `desktop pointer --screen <machine> <action> <x,y>` | Does the same at a point on the screen, without choosing a window or bringing one to the front. |
| `desktop windows <machine>` | Lists every visible window on the desktop, with the process that owns it, its position and size, and its title. |
| `desktop tray ls <machine>` | Lists the icons in the notification area beside the clock, including those hidden behind "Show hidden icons". |
| `desktop tray click <machine> <icon>` | Clicks the icon whose name starts with `<icon>`, opening the hidden icons first when it is there. `--button right` opens most programs' menus. |
| `desktop uac --program <exe> --consent <machine>` | Answers the Windows elevation prompt for that program. `--consent` accepts it and `--cancel` refuses it. `--user <admin> --password-stdin` enters an administrator's name and password. |

**Elements.** An element is named by a path of segments separated by `/`. **The first segment always names one of the process's windows**; each later segment is searched for anywhere inside what the segment before it found. So `Window[Orders]/Button[Save]` is the Save button in the window called `Orders`, while `Button[Save]` on its own looks for a *window* that is a button, and fails with `ELEMENT_NOT_FOUND`. When you do not know the window's title, `Window/Button[Save]` works while the process shows one window. A menu that a program opens is a window of its own. A Windows menu's window has the control type `Menu`: `Menu/MenuItem[Exit]`. A menu drawn by another framework may be an ordinary `Window`, as Avalonia's is: `Window/MenuItem[Exit]`. `desktop inspect` shows which. When the first segment matches no window, the tree in the error shows each window without its children, so an empty `children` there does not mean the window is empty.

Each segment may give, in this order: a control type (`Window`, `Button`, `Edit`), a name in square brackets, compared exactly and with case (`[Save]`), an automation ID after `#` (`#CustomerName`), and a position after `:`, counting from 1 (`:2`). It must give at least one of the first three. `Window[Orders]/Edit#CustomerName` names an edit box in the window called `Orders`, and `Window[Orders]/Button:2` the second button in it. `desktop inspect` shows the control types, names and automation IDs to use. Naming an element is sturdier than clicking a position, because it does not depend on the window's size or layout.

**Waiting.** A program shows its windows some time after it starts, and a window changes after a click. Wait for the element the next step needs with `desktop wait` instead of sleeping or polling `desktop inspect`: it returns as soon as the element exists, and fails with `TIMEOUT`, showing the window's elements, if it never does. A one-segment selector such as `"Window[Orders]"` waits for the window.

**Passwords.** `set-value`, `keys` and the pointer refuse a password field, so that a password cannot be typed by accident or end up in a log. To enter one, pass it on standard input: `printf '%s' "$password" | endia desktop set-value --secret-stdin orders-dev-dev-1 "$pid" "Window[Sign in]/Edit#Password"`. EastIndia writes it into the field and never prints, logs or reads it back.

**Notification-area icons.** A tray program's icon belongs to the Windows taskbar, not to the program, so the commands that take a process ID cannot reach it; `desktop tray` can. Icon names are the programs' tooltips, and many programs add their state to them, so `desktop tray click` takes the start of the name: `endia desktop tray click --button right orders-dev-dev-1 "Orders"` clicks `Orders: connected`. The menu that opens is a window of the tray program, so continue with its process ID: `desktop wait` and `desktop invoke` with `"Menu/MenuItem[Settings]"` for a Windows menu. Avalonia's menu is a `Window` whose items do not answer `invoke`: use `"Window/MenuItem[Settings]"` with `desktop click`.

**Positions.** Every position is in physical pixels, and there are two origins:

* **Relative to a window.** With a process ID, the position is measured from the top-left corner of the process's main window's client area: the inside of the window, below its title bar. `120,45` is 120 pixels right and 45 pixels down from there, wherever the window is.
* **Absolute on the screen.** With `--screen`, the position is measured from the top-left corner of the screen. `desktop windows` gives window positions on the same scale, so a point inside a window's rectangle there lands on that window, if no other window covers it.

`desktop inspect` gives each element two rectangles. `bounds` is measured from the window's outer top-left corner, which is not the client area's corner. `screenBounds` is measured from the top-left corner of the screen. To click an element, use `desktop click` with its selector, which brings the window to the front and clicks the centre of `screenBounds` for you.

**Process IDs.** Windows reuses process IDs. Every command that takes a process ID also takes `--started <time>`, the start time `process inspect` prints, such as `2026-10-05T14:03:22.1234567Z` (UTC), and refuses to act if the process with that ID started at another time.

**Elevation.** `desktop launch --elevated` starts a program with administrator rights, and is refused when the desktop user is a standard user. In that case, start the program normally and answer its elevation prompt with `desktop uac`.

**Windows of elevated programs.** The part of EastIndia that acts on the desktop runs as the desktop user without administrator rights. Windows does not let such a program press buttons, type or click in the windows of a program that runs with administrator rights, whether it was started with `desktop launch --elevated` or through an elevation prompt. So `invoke`, `click`, `set-value`, `keys`, `pointer`, `inspect`, and `wait` for an element inside such a window fail at once with `ACTION_UNSUPPORTED`, and the message says that the process runs elevated. What still works on those windows: `desktop screenshot`, `desktop windows`, `process inspect`, and `desktop wait` for the window itself, such as `"Window[Completely uninstall]"`. To get past a dialog of an elevated program:

* Start the program without `--elevated` when the test allows it; its dialogs can then be driven as usual.
* Use the program's own options for running without a dialog, such as a silent, headless or force switch.
* End the program with `endia process stop` once its work is done.

A machine whose image was built over a root image prepared before EastIndia 0.16.122 gives the earlier, less clear failures instead, such as `Process <pid> shows no window` or `Access is denied`; the cause is the same.

## Taking screenshots

```sh
shot=$(mktemp --suffix .png)
endia desktop screenshot orders-dev-dev-1 > "$shot"
endia desktop screenshot --pid "$pid" orders-dev-dev-1 > "$(mktemp --suffix .png)"
```

The screenshot comes back to the computer that runs `endia` as a PNG on standard output, so you decide where it goes: a temporary file, as above, or a program that reads the image directly. Nothing is saved on the PC or in the machine. `-o <file>` writes the image to that file instead and prints the file's full path. Without `--pid` the command captures the whole desktop; with `--pid` it captures that process's largest visible window.

## Reaching services on the PC

A machine can reach services that run on the PC. Each machine whose networks are not all internal has a card on the PC's `Default Switch`, which Windows in the machine names `internet`. The PC's address on the `Default Switch` is the machine's default gateway. A service on the PC answers a machine there when it listens on all of the PC's addresses and the Windows firewall lets the connection in.

For example, to keep a database in Docker on the PC and use it from a machine:

1. Publish the database's port on all the PC's addresses, which is Docker's default: `docker run -d -p 27017:27017 mongo`. A port published as `127.0.0.1:27017:27017` cannot be reached from a machine.
2. Allow the port through the PC's Windows firewall, for example with an inbound rule for TCP 27017 limited to the Default Switch's address range.
3. Give the PC a name in the machine with `extra_hosts` and the address `host-gateway`, as in Docker:

   ```yaml
   services:
     app:
       image: lab/app:dev
       extra_hosts:
         - "pc=host-gateway"
   ```

   The application then connects to `mongodb://pc:27017`. EastIndia writes the PC's current Default Switch address into the machine's hosts file each time the machine starts, because Windows chooses that address and can change it when the PC restarts. A service whose networks are all marked `internal: true` has no card on the Default Switch, so it cannot use `host-gateway`.

## Walkthrough 1: one machine kept running while you work on the software

Here one machine stays up all day while you change a Windows application. Each round copies in the new build, starts it, drives it, takes screenshots and checks the results, without rebuilding an image or restarting Windows.

1. **Bring the machine up once.** Use the one-service Compose file from "Deploying a single machine", with no main process, so that the machine keeps running:

   ```sh
   endia compose up --wait
   shots=$(mktemp -d)   # screenshots stay outside the project
   ```

2. **Deploy the build.** Build the application on your side, create its folder in the machine, then copy it in:

   ```sh
   endia exec orders-dev-dev-1 cmd /c "if not exist C:\app mkdir C:\app"
   endia cp ./publish/. orders-dev-dev-1:C:/app
   ```

3. **Run it on the desktop** and keep its process ID:

   ```sh
   pid=$(endia desktop launch orders-dev-dev-1 C:\\app\\Orders.exe | jq -r .processId)
   ```

4. **Interact with it.** Read the window's elements, then drive them:

   ```sh
   endia desktop inspect orders-dev-dev-1 "$pid" > ui.json
   endia desktop set-value orders-dev-dev-1 "$pid" "Window[Orders]/Edit#CustomerName" "Ada"
   endia desktop invoke orders-dev-dev-1 "$pid" "Window[Orders]/Button[Save]"
   ```

5. **Take screenshots** of the state you want to keep:

   ```sh
   endia desktop screenshot --pid "$pid" orders-dev-dev-1 > "$shots/after-save.png"
   ```

6. **Validate.** Run the test suite inside the machine and fetch its results, or call the application through its published port:

   ```sh
   endia exec orders-dev-dev-1 C:\\app\\tests\\run-tests.cmd
   endia cp orders-dev-dev-1:C:/app/tests/results ./results
   curl http://127.0.0.1:18080/health
   ```

7. **Fix and redeploy.** Stop the running application, change the code, and start again from step 2:

   ```sh
   endia process stop orders-dev-dev-1 "$pid"
   ```

When you finish, `endia compose down` removes the machine. If the machine gets into a bad state, `endia compose down` followed by `endia compose up --wait` gives a fresh one from the image in a few minutes.

## Walkthrough 2: a fleet of machines tested together

Here a test builds an image with the software under test and its Windows settings, starts several machines from it at once, tests them as one system, collects their results and shuts everything down.

1. **Build the layer.** `app.Endiafile` from "Built images" copies the application in, opens its firewall port, adds a hosts entry and sets a registry value:

   ```sh
   endia build -t lab/app:dev -f app.Endiafile .
   ```

2. **Describe the fleet.** Use the Compose file from "Deploying many machines": one server with a health check and three clients that wait for it, on one private network.

3. **Bring the fleet up.** Give each run its own project name, so that runs side by side do not collide, and make sure the fleet is always removed:

   ```sh
   set -e
   project="orders-test-$$"
   trap 'endia compose -p "$project" down -v' EXIT
   endia compose -p "$project" up --wait --wait-timeout 900   # seconds: 15 minutes
   ```

   `up --wait` exits with 1 if a machine becomes unhealthy, its main process exits, or the time-out passes.

4. **Run the coordinated test.** Start the clients' work and wait for each:

   ```sh
   pids=()
   for i in 1 2 3; do
     endia compose -p "$project" exec -T --index "$i" client C:\\app\\Client.exe --orders 100 &
     pids+=($!)
   done
   status=0
   for pid in "${pids[@]}"; do
     wait "$pid" || status=1
   done
   exit $status
   ```

   `-T` attaches no terminal, which suits a script. Each `exec` exits with the client program's exit code, and `wait` with a process ID returns that code. A bare `wait` returns 0 whatever the programs did, so the script names each process ID.

5. **Capture the results.** Copy each machine's result files out, and keep the server's output:

   ```sh
   for i in 1 2 3; do
     endia compose -p "$project" cp --index "$i" client:C:/app/results "./results/client-$i"
   done
   endia compose -p "$project" cp server:C:/app/logs ./results/server-logs
   endia compose -p "$project" logs server > ./results/server.log
   ```

6. **Shut the fleet down.** The shell's `trap` line from step 3 runs `endia compose -p "$project" down -v` when the script ends, whether it passed or failed. That removes the machines, the private network and the named volumes.

## Saying what a fleet is for and how far it has got

Several callers can use one PC at the same time: you, agents in sandboxes and test scripts. A **purpose** says what a fleet or machine is being used for. **Progress** is the caller's own count of how far that work has got. With both, the desktop app's Home page tells a run that is nearly done from one that has just begun, and a slow run from a stuck one, as long as the caller keeps its count up to date. EastIndia stores the counts, adds them up and draws them. It never estimates progress: a bar moves only when a caller reports a count.

### The purpose

Give a fleet its purpose when you launch it. A purpose has a title, one line given with `--purpose`, and optional notes, a Markdown file given with `--purpose-file`, such as what the run covers, whom to ask and what not to touch:

```sh
endia compose -p nightly up --wait --purpose "Nightly build and test" --purpose-file notes.md
```

Change it at any time with `endia update`, which names a fleet or a machine:

```sh
endia update nightly --purpose "Nightly build and test, retrying the login tests"
endia update nightly-runner-1 --purpose "Debugging the login timeout"
endia update nightly-runner-1 --purpose ""
```

- **A machine has its fleet's purpose** until it is given one of its own, which applies to that machine only. `endia update nightly-runner-1 --purpose ""` clears that machine's own purpose, and the machine then has the fleet's purpose again.
- **`--purpose` replaces the whole purpose,** so give `--purpose-file` again to keep the notes. `--purpose-file -` reads the notes from standard input.
- **The limits:** a title is 1 to 200 characters without a line break, and the notes are at most 65536 bytes of UTF-8.
- **Who set it:** the service records the caller with each purpose, which over HTTPS is the client certificate's name, such as `sandbox-1`.

`endia purpose show <fleet or machine>` prints the purpose in effect, who set it and when, then the notes. `--history` adds every change. When a fleet and a machine share a name, `endia update` and `endia purpose show` take `--fleet` or `--machine` to choose. `endia compose down` writes the fleet's history to its operation log before it removes the fleet, so the record outlives the run. `endia update` replaces the earlier `endia purpose set` and `endia purpose clear`, which no longer exist.

### Progress

A caller reports progress as counts of whatever it counts, such as files, tests or images:

| Option | Given to | Meaning |
|---|---|---|
| `--progress` | a machine | How much of the work the machine has done, a whole number from 0. |
| `--workload` | a fleet or a machine | The total amount of work, a whole number from 0. |
| `--stage` | a fleet | What the work is doing now, in your own words, 1 to 200 characters without a line break. |

A fleet's done figure is always the sum of its machines' progress, so a fleet takes no `--progress` count of its own. EastIndia shows a stage exactly as given and reads nothing from it, so a step number such as `Run tests 2/2` is part of your text.

- **The total is held in one place:** on the fleet or on its machines, never on both, because two totals for one piece of work could disagree. Whichever arrives first stays until it is removed. The other is refused with `PROGRESS_CONFLICT`, whose message says which holds the total: `nightly holds the workload; send the machine's progress only`, or `machines of nightly hold workloads; remove them first`.
- **A machine sends its workload with its progress,** in the same command. Progress alone is accepted; a workload alone is refused with `INVALID_REQUEST`.
- **A support machine sends 0 of 0.** A machine that only serves the others, such as a cache, sends `--progress 0 --workload 0` and is left out of the fleet's sums.
- **Progress above the workload** is accepted and shows as 100 per cent.
- **Stopped and exited machines keep their counts** in the fleet's sums, because work done stays done.
- **Setting a stage starts a new one.** It removes the machines' counts and workloads and the fleet's workload, and adds the stage that ended, with its final figures, to the history that `endia purpose show --history` prints. `--stage ""` ends the stage without starting another. A count is not added to the history, so send one as often as you like.

When the machines hold the workloads but a running machine has none, the fleet is open-ended: its bar shows how far the measured work has got, and that more work is still running.

### A nightly run

The fleet `nightly` has three runners and a cache, `nightly-shop-1`. In the first stage the fleet counts the images it builds; in the second each runner counts its own tests:

```sh
endia update nightly --purpose "Nightly build and test" --stage "Build images 1/2" --workload 3
endia update nightly-runner-1 --progress 1
endia update nightly --stage "Run tests 2/2"
endia update nightly-runner-1 --progress 30 --workload 120
endia update nightly-runner-2 --progress 20 --workload 80
endia update nightly-runner-3 --progress 10 --workload 100
endia update nightly-shop-1 --progress 0 --workload 0
endia update nightly --progress -1
```

1. After `endia update nightly-runner-1 --progress 1`, Home shows `Build images 1/2` with the bar at 33 per cent, 1 of 3.
2. `--stage "Run tests 2/2"` starts a new stage, which removes the counts and the fleet's workload, and adds `Build images 1/2` with 1 of 3 to the history. Home shows `Run tests 2/2` with the infinity bar until the runners report.
3. Once the runners have reported, Home shows 20 per cent, 60 of 300. `nightly-shop-1` is left out of the sums.
4. `endia update nightly --progress -1` removes the fleet's progress, and Home shows the infinity bar again while the fleet runs.

`endia update` prints the name of the fleet or machine it changed. `endia purpose show nightly` then prints `Stage: Run tests 2/2` and `Progress: 60 of 300 (20%)`; a support machine shows `Progress: 0 of 0 (support)`. `endia ps --format '{{.Progress.Progress}}'` prints each machine's count.

### Removing a value

As with Docker's `docker update --memory-swap -1`, -1 removes a number and `""` removes text:

| Option | Given to | What it removes |
|---|---|---|
| `--progress -1` | a machine | The machine's progress and its workload. |
| `--workload -1` | a machine | The machine's workload only. |
| `--workload -1` | a fleet | The fleet's workload, after which its machines may send their own. |
| `--progress -1` | a fleet | All the fleet's progress: its stage, its workload and every machine's counts. The stage that ends goes into the history. |
| `--stage ""` | a fleet | The stage, with the counts, as a new stage would. |
| `--purpose ""` | a fleet or a machine | The purpose, and with it the progress of the same fleet or machine. |

The service refuses a stage given to a machine with `INVALID_REQUEST`, because the fleet's stage covers its machines. `endia update` with no option, a count that is not a whole number from -1, a title with a line break, notes over 65536 bytes or `--purpose-file` without `--purpose` exit with 125, and nothing is sent. None of these changes is an operation: each command answers at once.

### What the desktop app shows

Home shows each running fleet's bar under its purpose. The fleet's purpose card, a machine's page, and the Progress columns of the fleet list and the machines table show bars too.

- **The ship bar,** for work with a total: the bar fills to the percentage, with a ship whose bow is at the end of the filled part. Beside it are the percentage, the stage, the counts and when they last changed: `Run tests 2/2, 60 of 300, updated about a minute ago`.
- **The infinity bar,** for running work with no total: a band of diagonal stripes moving left to right, with no ship and no percentage. Beside it are the stage and the done count when there is one, such as `Convert photos, 6,200`.
- **The ship with the infinity bar ahead,** for an open-ended fleet: the ship bar, with the stripes moving in the part not yet filled. It becomes the plain ship bar when the open-ended machines stop, and the infinity bar when the measured ones finish first.
- **No report:** a running fleet or machine that reports nothing shows the infinity bar. So does a support machine, with no words beside it. A stopped, exited or paused fleet or machine draws no bar, and keeps its counts.

The stripes stand still when Windows is set to show fewer animations. A screen reader reads the bar as its figure, such as `20 per cent, 60 of 300`, or as `Running, no total given`. EastIndia's own operations, such as a build, keep their plain progress bar, so the ship always means a caller's count.

From a program, the client libraries make the same change in one call: in Python `fleets.update("nightly", stage="Run tests 2/2")` and `machines.update("nightly-runner-1", progress=30, workload=120)`; in JavaScript `fleets.update("nightly", { stage: "Run tests 2/2" })` and `machines.update("nightly-runner-1", { progress: 30, workload: 120 })`.

## Driving EastIndia from a program

A test runner written in C#, Python or JavaScript can call EastIndia's API through a client library rather than run `endia` and read what it prints. Each library gives every answer as a typed record. A refusal arrives as an exception that carries the API's error code, such as `NOT_FOUND` or `TIMEOUT`. A program's exit code arrives in full: 3010 stays 3010.

| Language | Package | Guide |
|---|---|---|
| C# | NuGet `EastIndia.Client` (not yet published) | |
| Python 3.10 and later | PyPI `endia`, imported as `endia` | [endia-python](https://github.com/teaToolkit/endia-python/blob/main/REFERENCE.md) |
| Node 20 and later, with TypeScript types | npm `endia` | [endia-node](https://github.com/teaToolkit/endia-node/blob/main/REFERENCE.md) |

The Python library installs with `pip install endia` and is imported with `import endia`. Until EastIndia 0.16.80 it was shipped as a wheel named `eastindia_client`; `endia` has every public class and function that package had and reads the same environment variables, so moving to it means changing the import from `eastindia_client` to `endia`.

Each library connects from the environment as `endia` does, with `EastIndiaClient.FromEnvironment()`, `EastIndiaClient.from_env()` or `EastIndiaClient.fromEnv()`. It uses `EASTINDIA_HOST` with the certificate files in `EASTINDIA_CERT_PATH` when they are set, then the context that `EASTINDIA_CONTEXT` names, then the current context in `~/.eastindia`. A program that runs where `endia version` works therefore needs no settings of its own.

None of the libraries reads Compose files. To bring a fleet up, pass the project's resolved model, which `endia compose config --format json` prints. The library sends it with the build contexts and bind-mount sources, as `endia compose up` does.

## Limits to plan for

* **Two machines boot at a time.** The configuration key `maxParallelBoots` in `policy.json` changes the number.
* **12 GiB of the PC's memory stays free.** A machine that would leave less is refused with `CAPACITY_REFUSED`. The check uses each machine's starting memory, not the most it may grow to. The configuration key `hostReserveMiB` changes the reserve.
* **20 GiB of disk stays free** on the image folder's drive (`minFreeDiskGiB`).
* **A restart of the service** marks every operation that was running `interrupted`. A build or import removes its machines and disks; a fleet or machine operation leaves what it had done, and running `compose up` again continues the fleet. Fleet machines keep running, and the service picks them up again when it starts.

`--format json` gives any listing as JSON for a program to read, and `endia info --format json` prints the host's description and every setting in effect as one JSON object. The command line exits with 0 on success, 1 on a failure, 125 on a usage mistake (nothing is sent) and 130 after Ctrl+C. On a failure, standard error says why. `Error response from EastIndia: <message> (<CODE>)` means the service refused the request. `Cannot connect to the EastIndia service at <address>. Is the service running?` means the command could not reach the service. Ctrl+C during a long operation cancels it. A cancelled build or import removes what it created; a cancelled `compose up` stops before its next machine, and what it has done stays done. Once `compose up` without `-d` is following the machines' logs, the first Ctrl+C runs `compose stop` instead.

## When something goes wrong

* `Windows refused access to the EastIndia service` means your account is not in `eastindia-users`, or joined it after you signed in. The installer adds the person who ran it; sign out and in again after joining.
* `endia operation ls` lists the long-running work: builds, imports, `base prepare`, `compose up` and `compose down`, prunes and image-folder moves. `endia operation logs <id>` shows what it printed, and `endia operation cancel <id>` stops it as Ctrl+C does.
* `endia compose ps -a` and `endia ps -a` show every machine, including stopped ones, with its exit code.
* `endia compose logs <service>` shows what a machine's main process printed.
* `endia stats` shows each machine's processor, memory, disk and network use, and the PC's own processor and memory use.
* `endia info` lists records the service could not read, objects that no longer belong to anything, and interrupted operations.
* `endia system prune` deletes stopped machines, images that are not in use and objects that no longer belong to anything. An image is in use when a machine uses it or another image is built on it. Without `--all` (`-a`), only the images without a tag are deleted; with it, every image that is not in use is deleted, tagged or not. Volumes are never deleted by the prune. `endia system df` shows the disk space each kind uses.
