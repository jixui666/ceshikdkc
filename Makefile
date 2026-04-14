ARCHS = arm64 arm64e
TARGET = iphone:clang:15.0:14.0
INSTALL_TARGET_PROCESSES = Facebook

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PlanManageHijack

PlanManageHijack_FILES = Tweak.x
PlanManageHijack_FRAMEWORKS = UIKit WebKit
PlanManageHijack_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
