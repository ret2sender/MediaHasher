# MediaHasher - convenience wrapper around CMake.
#
# This Makefile does not build anything itself; it drives CMake so the common
# workflows are one word long. CMake remains the source of truth, and CLion
# users can ignore this file entirely.
#
#   make                build the application (Debug)
#   make -j6            same, six parallel jobs
#   make BUILD_TYPE=Release
#   make run            build, then run with logging attached to the terminal
#   make core           build the core library, CLI and tests standalone
#   make test           run the core unit tests
#   make bundle         make the .app self-contained (macOS)
#   make dmg            self-contained .app plus a .dmg (macOS)
#   make install        copy the bundle to /Applications (macOS)
#   make clean          remove build artifacts, keep the CMake configuration
#   make distclean      remove the build directory entirely
#   make help           list targets
#
# SPDX-License-Identifier: GPL-3.0-or-later

# ---------------------------------------------------------------------------
# Configuration - override on the command line, e.g. make BUILD_TYPE=Release
#
# Each build type gets its own directory. CMAKE_BUILD_TYPE is baked into the
# CMake cache at configure time, so sharing one directory between Debug and
# Release would silently keep whichever was configured first.
# ---------------------------------------------------------------------------
BUILD_TYPE     ?= Debug
BUILD_TYPE_LC  := $(shell echo $(BUILD_TYPE) | tr '[:upper:]' '[:lower:]')
APP_BUILD_DIR  ?= build/app-$(BUILD_TYPE_LC)
CORE_BUILD_DIR ?= build/core-$(BUILD_TYPE_LC)
GENERATOR      ?= Unix Makefiles

# ---------------------------------------------------------------------------
# Dependency discovery
#
# Qt has no standard install location on macOS, so CMake must be told where it
# is. QT_PREFIX is resolved in this order:
#
#   1. whatever is passed on the command line or set in the environment
#   2. Homebrew's qt formula
#   3. the Qt online installer's default location (~/Qt/6.x.x/macos)
#
# A candidate only counts if it actually contains Qt6Config.cmake: `brew
# --prefix qt` prints a path whether or not the formula is installed, so the
# path alone proves nothing.
# ---------------------------------------------------------------------------
QT_PREFIX ?=

ifeq ($(strip $(QT_PREFIX)),)
QT_PREFIX := $(shell brew --prefix qt 2>/dev/null)
endif
ifeq ($(wildcard $(QT_PREFIX)/lib/cmake/Qt6/Qt6Config.cmake),)
QT_PREFIX := $(lastword $(sort $(wildcard $(HOME)/Qt/6.*/macos)))
endif

QT_CONFIG := $(wildcard $(QT_PREFIX)/lib/cmake/Qt6/Qt6Config.cmake)

OPENSSL_PREFIX ?= $(shell brew --prefix openssl@3 2>/dev/null)

APP_BUNDLE := $(APP_BUILD_DIR)/MediaHasher.app
APP_BINARY := $(APP_BUNDLE)/Contents/MacOS/MediaHasher

# On Linux the target is a plain executable rather than a bundle.
UNAME_S := $(shell uname -s)
ifneq ($(UNAME_S),Darwin)
APP_BINARY := $(APP_BUILD_DIR)/MediaHasher
endif

CMAKE_COMMON := -DCMAKE_BUILD_TYPE=$(BUILD_TYPE)
ifneq ($(strip $(OPENSSL_PREFIX)),)
CMAKE_COMMON += -DOPENSSL_ROOT_DIR=$(OPENSSL_PREFIX)
endif

CMAKE_APP_FLAGS := $(CMAKE_COMMON)
ifneq ($(strip $(QT_PREFIX)),)
CMAKE_APP_FLAGS += -DCMAKE_PREFIX_PATH=$(QT_PREFIX)
endif

.DEFAULT_GOAL := app
.PHONY: all app core check-qt configure configure-core run test bundle dmg \
        install clean distclean help

all: app

# ---------------------------------------------------------------------------
# Qt preflight
#
# Without this, a missing Qt surfaces much later as an opaque
# "Could not find a package configuration file provided by Qt6" from CMake.
# ---------------------------------------------------------------------------
check-qt:
	@if [ -z "$(strip $(QT_PREFIX))" ] || [ -z "$(strip $(QT_CONFIG))" ]; then \
		echo "error: Qt 6 not found."; \
		echo; \
		if [ -n "$(strip $(QT_PREFIX))" ]; then \
			echo "  Looked in : $(QT_PREFIX)"; \
			echo "  Expected  : $(QT_PREFIX)/lib/cmake/Qt6/Qt6Config.cmake"; \
			echo; \
		fi; \
		echo "  Install Qt via Homebrew:"; \
		echo "      brew install qt"; \
		echo; \
		echo "  Or point this build at an existing installation:"; \
		echo "      make QT_PREFIX=\"\$$(brew --prefix qt)\""; \
		echo "      make QT_PREFIX=\$$HOME/Qt/6.11.0/macos"; \
		echo; \
		exit 1; \
	fi

# ---------------------------------------------------------------------------
# Application (builds the core library too, via add_subdirectory)
# ---------------------------------------------------------------------------
$(APP_BUILD_DIR)/Makefile: | check-qt
	cmake -S ui -B $(APP_BUILD_DIR) -G "$(GENERATOR)" $(CMAKE_APP_FLAGS)

configure: check-qt
	cmake -S ui -B $(APP_BUILD_DIR) -G "$(GENERATOR)" $(CMAKE_APP_FLAGS)

# Recursive make so that -jN reaches the real build through the jobserver.
app: $(APP_BUILD_DIR)/Makefile
	+$(MAKE) -C $(APP_BUILD_DIR)

run: app
	$(APP_BINARY)

# ---------------------------------------------------------------------------
# Core library, CLI and unit tests, built standalone
#
# Tests are built only when MediaHash is the top-level project, which is why
# they live here rather than in the application build.
# ---------------------------------------------------------------------------
$(CORE_BUILD_DIR)/Makefile:
	cmake -S MediaHash -B $(CORE_BUILD_DIR) -G "$(GENERATOR)" $(CMAKE_COMMON)

configure-core:
	cmake -S MediaHash -B $(CORE_BUILD_DIR) -G "$(GENERATOR)" $(CMAKE_COMMON)

core: $(CORE_BUILD_DIR)/Makefile
	+$(MAKE) -C $(CORE_BUILD_DIR)

test: core
	ctest --test-dir $(CORE_BUILD_DIR) --output-on-failure

# ---------------------------------------------------------------------------
# macOS packaging
# ---------------------------------------------------------------------------
bundle: app
	QT_PREFIX="$(QT_PREFIX)" ./scripts/macdeploy.sh $(APP_BUNDLE)

# BUILD_TYPE is forwarded so the .dmg name reflects what is inside it:
# 'make dmg' (Debug by default) yields ...-debug.dmg, while
# 'make BUILD_TYPE=Release dmg' yields the clean release name.
dmg: app
	QT_PREFIX="$(QT_PREFIX)" BUILD_TYPE="$(BUILD_TYPE)" ./scripts/macdeploy.sh $(APP_BUNDLE) --dmg

install: bundle
	rm -rf /Applications/MediaHasher.app
	cp -R $(APP_BUNDLE) /Applications/
	@echo "Installed /Applications/MediaHasher.app"

# ---------------------------------------------------------------------------
# Cleaning
# ---------------------------------------------------------------------------
clean:
	@if [ -f $(APP_BUILD_DIR)/Makefile ]; then \
		$(MAKE) -C $(APP_BUILD_DIR) clean; \
	else \
		echo "nothing to clean in $(APP_BUILD_DIR)"; \
	fi
	@if [ -f $(CORE_BUILD_DIR)/Makefile ]; then \
		$(MAKE) -C $(CORE_BUILD_DIR) clean; \
	else \
		echo "nothing to clean in $(CORE_BUILD_DIR)"; \
	fi

distclean:
	rm -rf build

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
help:
	@echo "MediaHasher - available targets"
	@echo
	@echo "  app         Build the application (default). Builds the core too."
	@echo "  run         Build, then run with logging on the terminal."
	@echo "  core        Build the core library, CLI and tests standalone."
	@echo "  test        Run the core unit tests via ctest."
	@echo "  bundle      macOS: make the .app self-contained."
	@echo "  dmg         macOS: self-contained .app plus a .dmg."
	@echo "  install     macOS: copy the bundle to /Applications."
	@echo "  configure   Re-run CMake for the application."
	@echo "  clean       Remove build artifacts, keep the CMake configuration."
	@echo "  distclean   Remove the build directory entirely."
	@echo
	@echo "Common workflows:"
	@echo "  make -j6                        development build"
	@echo "  make run                        build and run with logging"
	@echo "  make BUILD_TYPE=Release dmg     distributable disk image"
	@echo "  make BUILD_TYPE=Release install install to /Applications"
	@echo
	@echo "Variables (override on the command line):"
	@echo "  BUILD_TYPE=$(BUILD_TYPE)"
	@echo "  APP_BUILD_DIR=$(APP_BUILD_DIR)"
	@echo "  CORE_BUILD_DIR=$(CORE_BUILD_DIR)"
	@echo "  GENERATOR=$(GENERATOR)"
	@echo "  QT_PREFIX=$(QT_PREFIX)"
	@echo "  OPENSSL_PREFIX=$(OPENSSL_PREFIX)"
