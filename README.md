# wrapper

A tool to decrypt Apple Music songs. An active subscription is still needed.

Supports only x86_64 and arm64 Linux.

## Installation

Installation methods:

- Prebuilt binaries (from [releases](https://github.com/WorldObservationLog/wrapper/releases) or [actions](https://github.com/WorldObservationLog/wrapper/actions))
- [Build from source](#build-from-source)

### Automated Setup (Recommended)

You can download, build the wrapper, perform the initial login, and configure the systemd service automatically with a single command. 

```bash
curl -fsSL https://raw.githubusercontent.com/LuciKritZ/am-wrapper/main/install.sh | bash
```

This script will clone the repository, install all dependencies (LLVM, Android NDK), compile the wrapper, guide you through the 2FA login, and configure it to run seamlessly in the background as a systemd service.

## Usage

```
Usage: wrapper [OPTION]...

  -h, --help              Print help and exit
  -V, --version           Print version and exit
  -H, --host=STRING         (default=`127.0.0.1')
  -D, --decrypt-port=INT    (default=`10020')
  -M, --m3u8-port=INT       (default=`20020')
  -A, --account-port=INT    (default=`30020')
  -P, --proxy=STRING        (default=`')
  -L, --login=STRING        (username:password)
  -F, --code-from-file      (default=off)
```

## Special thanks

- Anonymous, for providing the original version of this project and the legacy Frida decryption method.
- chocomint, for providing support for arm64 arch.
