#
# Makefile to create distribution archives for WinSparkle.
# Needs GNU Make.
#


# The version to package. It is assumed that binaries in the tree are
# for this version.
VERSION := $(shell git describe | sed -e 's/^v//g')


sources_base := WinSparkle-$(VERSION)-src
binary_base  := WinSparkle-$(VERSION)
sources_arch := $(sources_base).7z
binary_arch  := $(binary_base).zip
binary_files := \
	include/winsparkle.h \
	include/winsparkle-version.h \
	Release/WinSparkle.dll \
	Release/WinSparkle.lib \
	Release/WinSparkle.pdb \
	x64/Release/WinSparkle.dll \
	x64/Release/WinSparkle.lib \
	x64/Release/WinSparkle.pdb \
	AUTHORS COPYING NEWS README.md


all: binary sources
binary: $(binary_arch)
sources: $(sources_arch)

$(binary_arch): $(binary_files)
	@rm -rf $(binary_base) $@
	@mkdir $(binary_base)
	@mkdir -p $(binary_base)/include
	@mkdir -p $(binary_base)/Release
	@mkdir -p $(binary_base)/x64/Release
	for i in $(binary_files); do cp -a $$i $(binary_base)/$$i ; done
	zip -9 -r  $@ $(binary_base)
	@rm -rf $(binary_base) $(binary_base).tar

$(sources_arch):
	@rm -rf $(sources_base) $@
	git archive --prefix=$(sources_base)/ -o $(sources_base).tar HEAD
	tar xf $(sources_base).tar
	7z a -m0=lzma -mx=9 $@  $(sources_base)
	@rm -rf $(sources_base) $(sources_base).tar


clean:
	rm -f $(binary_arch)
	rm -f $(sources_arch)


.PHONY: all binary sources clean
