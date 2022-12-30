export PREFIX = $(THEOS)/toolchain/Xcode11.xctoolchain/usr/bin/

TARGET := iphone:clang:14.5:8.0
ARCHS := armv7 armv7s arm64 arm64e

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = libundirect

libundirect_FILES = libundirect.m HookCompat.m
libundirect_CFLAGS = -fobjc-arc
libundirect_INSTALL_PATH = /usr/lib
libundirect_EXTRA_FRAMEWORKS = CydiaSubstrate

include $(THEOS_MAKE_PATH)/library.mk
