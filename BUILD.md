# Building curl for AmigaOS 3 (clib2)

This guide describes how to build `curl` for **AmigaOS 3** using a cross-compilation setup with `m68k-amigaos-gcc` and the `clib2` runtime. Multiple binaries are built for different CPU targets: 68000, 68020, 68040, and 68060.

---

## ✅ Requirements

- **Amiga cross-compiler** (`m68k-amigaos-gcc`), GCC 13 preferred
- Working `pkg-config` (or stub with `PKG_CONFIG=true`)
- `clib2` support in your cross-compiler
- `amissl` linked and available
- Zlib, libatomic (if not built-in), and libunix as static libraries

---

## ⚙️ Common Configuration Options

All builds use the following options:

```bash
./buildconf && PKG_CONFIG=true ./configure \
  --host=m68k-amigaos \
  CC=m68k-amigaos-gcc \
  --disable-shared \
  --disable-ipv6 \
  --prefix=/opt/amiga13 \
  --disable-netrc \
  --without-libpsl \
  --with-amissl \
  --disable-threaded-resolver \
  CFLAGS="<CPU_FLAGS> -O0 -msoft-float -mcrt=clib2" \
  CPPFLAGS="" \
  LIBS="-lnet -lm -lc -lz -lunix -latomic"

Build Steps (Repeat for Each CPU Target)
Build for 68000

make clean
./buildconf && PKG_CONFIG=true ./configure \
  CFLAGS="-m68000 -O0 -msoft-float -mcrt=clib2" \
  [other flags as above]
make
cp src/curl ../curl-release/curl
cp lib/.libs/libcurl.* ../curl-release/

Build for 68020
make clean
./buildconf && PKG_CONFIG=true ./configure \
  CFLAGS="-m68020 -O0 -msoft-float -mcrt=clib2" \
  [other flags as above]
make
cp src/curl ../curl-release/curl.020
cp lib/.libs/libcurl.* ../curl-release/

Build for 68040
make clean
./buildconf && PKG_CONFIG=true ./configure \
  CFLAGS="-m68040 -O0 -msoft-float -mcrt=clib2" \
  [other flags as above]
make
cp src/curl ../curl-release/curl.040
cp lib/.libs/libcurl.* ../curl-release/

Build for 68060
make clean
./buildconf && PKG_CONFIG=true ./configure \
  CFLAGS="-m68060 -O0 -msoft-float -mcrt=clib2" \
  [other flags as above]
make
cp src/curl ../curl-release/curl.060
cp lib/.libs/libcurl.* ../curl-release/

📁 Output Structure
All builds are copied to ../curl-release/ with CPU-specific names:

curl               → 68000 version
curl.020           → 68020 version
curl.040           → 68040 version
curl.060           → 68060 version
libcurl.a.*        → Static lib variants

Notes
If libatomic or libunix are missing in your toolchain, ensure they're built and linked statically.

-O0 is used to prevent optimizer issues with clib2. Adjust as needed.

The --prefix value isn’t essential unless doing staged installs.

amissl support must be present at link time and runtime.
Related
curl main site: https://curl.se

Amiga cross-toolchain: https://github.com/bebbo/amiga-gcc

clib2: https://github.com/sba1/adtools/tree/master/clib2

