TARGET := iphone:clang:latest:8.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TOOL_NAME = classdumpctl

classdumpctl_FILES = Sources/classdumpctl/main.m
classdumpctl_FILES += $(wildcard ClassDumpRuntime/Sources/ClassDumpRuntime/ClassDump/*/*.m)
classdumpctl_FILES += $(wildcard ClassDumpRuntime/Sources/ClassDumpRuntime/ClassDump/*/*/*.m)

classdumpctl_CFLAGS = -fobjc-arc -I ClassDumpRuntime/Sources/ClassDumpRuntime/include
classdumpctl_CODESIGN_FLAGS = -Sentitlements.plist
classdumpctl_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk
