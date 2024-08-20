TARGET := iphone:clang:latest:8.0
INSTALL_TARGET_PROCESSES := SpringBoard
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ClassDumpTweak

ClassDumpTweak_FILES = Tweak.x
ClassDumpTweak_FILES += $(wildcard ClassDumpRuntime/Sources/ClassDumpRuntime/ClassDump/*/*.m)
ClassDumpTweak_FILES += $(wildcard ClassDumpRuntime/Sources/ClassDumpRuntime/ClassDump/*/*/*.m)

ClassDumpTweak_CFLAGS = -fobjc-arc -I ClassDumpRuntime/Sources/ClassDumpRuntime/include

include $(THEOS_MAKE_PATH)/tweak.mk
