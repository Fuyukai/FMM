# Makefile for NimBA

all: build

# standard build
build:
	nimble build --verbose

# cross-compile
build_win64:
	nimble build --os:windows --cpu:amd64 --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc

build_win32:
	nimble build --os:windows --cpu:amd64 --gcc.exe:i686-w64-mingw32-gcc -gcc.linkerexe:i686-w64-mingw32-gcc

clean:
	rm -rv src/nimcache
	rm -r bin/fmm