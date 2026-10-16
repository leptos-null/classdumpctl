# The Theos SDKs are patched to support building for armv7
# even after the Xcode versions stopped shipping armv7 slices.
# At the time of writing, 16.5 is the latest iOS SDK that Theos provides.
TARGET := iphone:clang:16.5:6.0
ARCHS := armv7 arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = classdumpctl

classdumpctl_FILES = Sources/classdumpctl/main.m
classdumpctl_FILES += $(wildcard ClassDumpRuntime/Sources/ClassDumpRuntime/ClassDump/*/*.m)
classdumpctl_FILES += $(wildcard ClassDumpRuntime/Sources/ClassDumpRuntime/ClassDump/*/*/*.m)

classdumpctl_CFLAGS = -fobjc-arc -I ClassDumpRuntime/Sources/ClassDumpRuntime/include
classdumpctl_CODESIGN_FLAGS = -Sentitlements.plist
classdumpctl_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk
