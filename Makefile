# Makefile for NimBA

all: build

build:
	nimble build --verbose

run: build
	cd bin; ./fmm

clean:
	rm -rv src/nimcache
	rm -r bin/fmm