ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET := iphone:clang:16.2:15.0
ARCHS := arm64 arm64e
else
TARGET := iphone:clang:14.5:7.0
ARCHS := armv7 armv7s arm64 arm64e
endif

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = libundirect

libundirect_FILES = libundirect.m HookCompat.m
libundirect_CFLAGS = -fobjc-arc
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
libundirect_LDFLAGS += -install_name @rpath/libundirect.dylib
endif
libundirect_INSTALL_PATH = /usr/lib
libundirect_EXTRA_FRAMEWORKS = CydiaSubstrate

include $(THEOS_MAKE_PATH)/library.mk
