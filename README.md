# East India

East India gives automated tests real Windows desktops to work in. You describe Windows images in Dockerfile-style recipes, called Endiafiles, and the machines that run them in Compose files. East India creates each machine as a Hyper-V virtual machine, and your tests run programs in it, copy files in and out, drive its desktop and take screenshots. If you know Docker and Docker Compose, you already know most of East India.

This repository holds the releases and the user documentation. The service's source code is private.

## Install

East India needs a Windows PC with Hyper-V enabled, running Windows 11 Pro or Enterprise, x64, build 26100 or later.

1. Download `eastindia-<version>.msi` from the [Releases page](https://github.com/teaToolkit/endia/releases). It installs the East India service and the command line, `endia.exe`.
2. Install it, naming the folder that will hold your images:

   ```
   msiexec /i eastindia-<version>.msi IMAGEFOLDER=M:\eastindia
   ```

To run the command line on Linux, such as in a Docker sandbox on the same PC, download `endia-linux-x64` from the same Releases page.

## Documentation

| Document | What it covers |
|---|---|
| [Using East India](docs/using-eastindia.md) | Installing the service and using it: building and layering images, deploying one machine or many, working inside running machines, controlling the desktop and taking screenshots, with two complete walkthroughs. Written for people and for AI agents. |
| [Testing Windows applications](docs/testing-windows-apps.md) | Testing a Windows service, desktop program or tray program on real Windows, including several talking over a network. |
| [Windows app testing sample](samples/windows-app-testing/) | The complete working example that the testing guide uses: a Windows service, a desktop program and a tray program, an image recipe, a Compose file and `run-tests.sh`. |

## Client libraries

A test runner can call East India's API directly instead of running `endia`.

| Language | Install | Source and reference |
|---|---|---|
| Python 3.10 and later | `pip install endia` | [endia-python](https://github.com/teaToolkit/endia-python) |
| Node 20 and later | `npm install endia` | [endia-node](https://github.com/teaToolkit/endia-node) |

## Licence

MIT. See [LICENSE](LICENSE).
