<!--
Copyright (C) Daniel Stenberg, <daniel@haxx.se>, et al.

SPDX-License-Identifier: curl
-->

# curl for AmigaOS

This document describes the AmigaOS 3.x binary archive for curl 8.22.0-DEV
and libcurl 8.22.0-DEV.

```text
curl 8.22.0-DEV
-------------------------------------
libcurl/8.22.0-DEV AmiSSL/5.x OpenSSL/3.x zlib/1.3.1
Protocols: dict file ftp ftps gopher gophers http https imap imaps
           ipfs ipns mqtt pop3 pop3s rtsp smb smbs smtp smtps telnet
           tftp ws wss
Features:  alt-svc HSTS HTTPS-proxy libz NTLM SSL TLS-SRP threadsafe
```

curl is a command line tool for transferring data specified with URL syntax.
The archive also includes libcurl, which allows Amiga developers to link curl
functionality directly into their own applications.

The AmigaOS archive is tested on multiple CPU targets and SSL workloads.

## System requirements

- AmiSSL v5.0 or newer (mandatory)
- AmigaOS 3.x (3.2.2.1 tested, works on 3.0-3.1)
- 68000, 68020, 68030, 68040, or 68060 CPU (no FPU required)
- Minimum stack: 32768 bytes
  - AmigaOS 3.1.4 and newer auto-select the correct stack
  - Older versions: set it manually with `STACK 32768`
- Roadshow TCP tested
- WinUAE TCP tested
- Real hardware and emulation tested

## What's new in 8.22.0-DEV

- Updated to the current upstream curl development snapshot.
- Retested all supported CPU targets: 68000, 68020, 68030, 68040, and 68060.
- Added a dedicated 68030 executable and static libcurl library.
- Uses the known-good GCC 13.2 m68k-amigaos toolchain after GCC 15.2 builds
  were found to crash at runtime on AmigaOS.
- Uses the clib2 runtime, soft-float ABI, dynamic AmiSSL linking and `-O0` for
  stable release builds.
- Added repeatable multi-CPU release and Aminet packaging tools.

## Files included

| File | Description |
| ---- | ----------- |
| `curl` | 68000 binary |
| `curl.020` | 68020 binary |
| `curl.030` | 68030 binary |
| `curl.040` | 68040 binary |
| `curl.060` | 68060 binary |
| `libcurl.a` | static library (68000) |
| `libcurl.a.020` | static library (68020) |
| `libcurl.a.030` | static library (68030) |
| `libcurl.a.040` | static library (68040) |
| `libcurl.a.060` | static library (68060) |

Developers should use the matching libcurl library for their target CPU when
building Amiga applications.

## Developer information

Tested release compiler:

```text
m68k-amigaos-gcc (GCC) 13.2.0
```

GCC 13.2 is currently the known-good release compiler for this port. GCC 15.2
builds have shown runtime crashes on AmigaOS and are not recommended for
release binaries at this time.

### Automated release build

The repository includes a reusable release builder for all CPU targets:

```sh
make -f Makefile.amiga release
```

To build only selected targets:

```sh
make -f Makefile.amiga release CPUS="020 030 040 060"
```

The builder uses separate out-of-tree directories, records the compiler and
Git revision, copies the matching executables and static libraries, includes
public headers and documentation, generates SHA-256 checksums, and creates a
release archive under `dist-amiga/`.

Individual targets can also be built directly:

```sh
make -f Makefile.amiga 030
```

### Aminet package

A complete Aminet-ready build, including the generated `.readme`, is prepared
with:

```sh
make -f Makefile.amiga aminet
```

The readme template is stored at `packages/AmigaOS/curl.readme.in`. The Aminet
readme is generated with the current curl version and date, placed inside the
release drawer, and copied beside the archive under `dist-amiga/`.

To create the LHA automatically when the `lha` command is installed:

```sh
make -f Makefile.amiga aminet-lha
```

The Aminet version and replacement package can be overridden when required:

```sh
AMINET_VERSION=8.22-DEV-210726 \
AMINET_REPLACES=comm/tcp/curl-8.18-DEV-18112025.lha \
make -f Makefile.amiga aminet
```

### Manual 68000 build

```sh
autoreconf -fi

rm -rf build-amiga-000
mkdir build-amiga-000
cd build-amiga-000

PKG_CONFIG=true ../configure \
  --host=m68k-amigaos \
  CC=/opt/amiga/bin/m68k-amigaos-gcc \
  AR=/opt/amiga/bin/m68k-amigaos-ar \
  RANLIB=/opt/amiga/bin/m68k-amigaos-ranlib \
  --disable-shared \
  --disable-ipv6 \
  --prefix=/opt/amiga \
  --disable-netrc \
  --without-libpsl \
  --with-amissl \
  --with-zlib \
  --disable-threaded-resolver \
  CFLAGS="-m68000 -O0 -msoft-float -mcrt=clib2" \
  LIBS="-lnet -lc -lz -lunix -latomic -lgcc -lm"

make -j1 V=1
```

The static library order is significant. In particular, `-lgcc` must appear
before the final `-lm` so that GCC soft-float helpers such as `__adddf3` are
resolved without pulling in a second clib2 constructor definition.

For the other CPU targets, use the same procedure and replace `-m68000` with
`-m68020`, `-m68030`, `-m68040`, or `-m68060` in `CFLAGS`.

Source code for this AmigaOS port is available at:

<https://github.com/boingball/curl>

## Release notes

### curl 8.22.0-DEV - 2026-07-21

- Updated to the current upstream development snapshot
- Built with the known-good GCC 13.2 release toolchain
- Added dedicated 68030 executable and static library builds
- Added repeatable multi-CPU and Aminet packaging tools

### curl 8.18.0-DEV - 2025-11-18

- Increased stack cookie to 32768 for TLS stability
- Added CPU-specific libcurl libraries
- Reviewed minor AmigaOS fixes upstream

### curl 8.11.2-DEV - 2024-11-26

- Added stack cookie 16384
- Improved TLS robustness

### curl 8.11.1-DEV - 2024-11-24

- Initial modern port of curl 8.11 for AmigaOS 3.x

## Distribution

Study the `COPYING` file for distribution terms.
