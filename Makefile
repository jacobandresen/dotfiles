.PHONY: install install-nvim install-zsh install-mc install-pi install-skills install-fonts install-icon setup-jupyter setup-lmstudio setup-host deps deps-arch deps-debian deps-ubuntu deps-macos

OS := $(shell uname -s)

install: deps install-nvim install-zsh install-mc install-pi

DISTRO_ID := $(shell . /etc/os-release 2>/dev/null && echo $$ID)

deps:
ifeq ($(OS),Darwin)
	$(MAKE) deps-macos
else ifneq ($(wildcard /etc/arch-release),)
	$(MAKE) deps-arch
else ifeq ($(DISTRO_ID),ubuntu)
	$(MAKE) deps-ubuntu
else ifneq ($(wildcard /etc/debian_version),)
	$(MAKE) deps-debian
else
	$(error Unsupported OS: $(OS))
endif
	$(MAKE) install-fonts

deps-macos:
	@command -v brew >/dev/null 2>&1 || { echo "Installing Homebrew..."; /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; }
	brew install git neovim ollama pi
	brew install --cask wezterm lm-studio font-terminess-ttf-nerd-font

deps-arch:
	sudo pacman -Syu --needed git neovim wezterm ollama
	@echo "Install Terminess Nerd Font from https://www.nerdfonts.com/font-downloads"

deps-ubuntu:
	sudo apt-get update
	sudo apt-get install -y git curl python3
	@echo "Installing Neovim from PPA (apt version is often outdated)..."
	sudo apt-get install -y software-properties-common
	sudo add-apt-repository -y ppa:neovim-ppa/unstable
	sudo apt-get update
	sudo apt-get install -y neovim
	@echo "Installing pi..."
	@curl -fsSL https://pi.dev/install.sh | bash
	@echo "Install LM Studio from https://lmstudio.ai (download the Linux AppImage or .deb)"
	@echo "Install WezTerm from https://wezfurlong.org/wezterm/install/linux.html"
	@echo "Install Terminess Nerd Font from https://www.nerdfonts.com/font-downloads"

deps-debian:
	sudo apt-get update
	sudo apt-get install -y git curl python3
	@echo "Installing Neovim from PPA (apt version is often outdated)..."
	sudo apt-get install -y software-properties-common
	sudo add-apt-repository -y ppa:neovim-ppa/unstable
	sudo apt-get update
	sudo apt-get install -y neovim
	@echo "Installing pi..."
	@curl -fsSL https://pi.dev/install.sh | bash
	@echo "Install LM Studio from https://lmstudio.ai (download the Linux AppImage or .deb)"
	@echo "Install WezTerm from https://wezfurlong.org/wezterm/install/linux.html"
	@echo "Install Terminess Nerd Font from https://www.nerdfonts.com/font-downloads"

install-nvim:
	@echo "Installing nvim config..."
	@mkdir -p $(HOME)/.config
	@if [ -L $(HOME)/.config/nvim ]; then \
		echo "  ✓ ~/.config/nvim already symlinked"; \
	elif [ -e $(HOME)/.config/nvim ]; then \
		echo "  ⚠ ~/.config/nvim exists but is not a symlink — skipping"; \
	else \
		ln -s $(CURDIR)/nvim $(HOME)/.config/nvim; \
		echo "  ✓ ~/.config/nvim -> $(CURDIR)/nvim"; \
	fi

install-zsh:
	@echo "Installing zsh config..."
	@if [ -L $(HOME)/.zshrc ]; then \
		echo "  ✓ ~/.zshrc already symlinked"; \
	elif [ -e $(HOME)/.zshrc ]; then \
		mv $(HOME)/.zshrc $(HOME)/.zshrc.bak; \
		ln -s $(CURDIR)/.zshrc $(HOME)/.zshrc; \
		echo "  ✓ backed up old ~/.zshrc -> ~/.zshrc.bak, linked repo copy"; \
	else \
		ln -s $(CURDIR)/.zshrc $(HOME)/.zshrc; \
		echo "  ✓ ~/.zshrc -> $(CURDIR)/.zshrc"; \
	fi

install-mc:
	@echo "Installing Midnight Commander config..."
	@mkdir -p $(HOME)/.config/mc
	@if [ -L $(HOME)/.config/mc/ini ]; then \
		echo "  ✓ ~/.config/mc/ini already symlinked"; \
	elif [ -e $(HOME)/.config/mc/ini ]; then \
		mv $(HOME)/.config/mc/ini $(HOME)/.config/mc/ini.bak; \
		ln -s $(CURDIR)/mc/ini $(HOME)/.config/mc/ini; \
		echo "  ✓ backed up old ini -> ini.bak, linked repo copy"; \
	else \
		ln -s $(CURDIR)/mc/ini $(HOME)/.config/mc/ini; \
		echo "  ✓ ~/.config/mc/ini -> $(CURDIR)/mc/ini"; \
	fi

install-pi: install-skills
	@echo "Installing pi agent config..."
	@mkdir -p $(HOME)/.pi/agent
	@cp pi/agent/models.json $(HOME)/.pi/agent/models.json
	@cp pi/agent/settings.json $(HOME)/.pi/agent/settings.json
	@echo "  ✓ models.json"
	@echo "  ✓ settings.json"

FONT_DIR := $(HOME)/.local/share/fonts
HACK_NERD_URL := https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.tar.xz
# C64 Pro Mono is fetched at install time, not committed: its license forbids
# redistributing the .ttf but permits download from the official source.
C64_FONT_URL := https://style64.org/file/C64_TrueType_v1.2.1-STYLE.zip
C64_FONT_TTF := fonts/C64_Pro_Mono-STYLE.ttf

install-fonts:
	@echo "Installing Hack Nerd Font..."
ifeq ($(OS),Darwin)
	@if fc-list 2>/dev/null | grep -qi "Hack Nerd Font"; then \
		echo "  ✓ Hack Nerd Font already installed"; \
	else \
		brew install --cask font-hack-nerd-font; \
	fi
	@echo "Installing C64 Pro Mono..."
	@if fc-list 2>/dev/null | grep -qi "C64 Pro Mono" || [ -f "$(HOME)/Library/Fonts/C64_Pro_Mono-STYLE.ttf" ]; then \
		echo "  ✓ C64 Pro Mono already installed"; \
	else \
		tmp=$$(mktemp -d) && \
		echo "  ↓ downloading C64 Pro Mono from style64.org..." && \
		curl -fsSL "$(C64_FONT_URL)" -o "$$tmp/c64.zip" && \
		( cd "$$tmp" && unzip -qo c64.zip ) && \
		cp "$$tmp"/*/$(C64_FONT_TTF) "$(HOME)/Library/Fonts/" && \
		rm -rf "$$tmp" && \
		echo "  ✓ C64 Pro Mono -> ~/Library/Fonts/C64_Pro_Mono-STYLE.ttf"; \
	fi
else
	@if fc-list | grep -qi "Hack Nerd Font"; then \
		echo "  ✓ Hack Nerd Font already installed"; \
	else \
		tmp=$$(mktemp -d) && \
		echo "  ↓ downloading Hack.tar.xz..." && \
		curl -fsSL "$(HACK_NERD_URL)" -o "$$tmp/Hack.tar.xz" && \
		mkdir -p "$(FONT_DIR)/HackNerdFont" && \
		tar -xJf "$$tmp/Hack.tar.xz" -C "$(FONT_DIR)/HackNerdFont" && \
		rm -rf "$$tmp" && \
		fc-cache -f "$(FONT_DIR)" >/dev/null 2>&1 && \
		echo "  ✓ Hack Nerd Font -> $(FONT_DIR)/HackNerdFont"; \
	fi
	@echo "Installing C64 Pro Mono..."
	@if fc-list | grep -qi "C64 Pro Mono"; then \
		echo "  ✓ C64 Pro Mono already installed"; \
	else \
		tmp=$$(mktemp -d) && \
		echo "  ↓ downloading C64 Pro Mono from style64.org..." && \
		curl -fsSL "$(C64_FONT_URL)" -o "$$tmp/c64.zip" && \
		( cd "$$tmp" && unzip -qo c64.zip ) && \
		mkdir -p "$(FONT_DIR)/C64ProMono" && \
		cp "$$tmp"/*/$(C64_FONT_TTF) "$(FONT_DIR)/C64ProMono/" && \
		rm -rf "$$tmp" && \
		fc-cache -f "$(FONT_DIR)" >/dev/null 2>&1 && \
		echo "  ✓ C64 Pro Mono -> $(FONT_DIR)/C64ProMono"; \
	fi
endif

# Custom "C64" wezterm icon (light-blue PETSCII on the C64 blue screen). The PNGs
# are committed (rendered output is fine under the C64 Pro license — only the .ttf
# itself can't be redistributed). Standalone on purpose: NOT in the `install`
# chain because the macOS path edits the WezTerm.app bundle (see caveats below).
ICON_SRC  := $(CURDIR)/icons/wezterm
ICON_NAME := org.wezfurlong.wezterm

install-icon:
	@echo "Installing C64 wezterm icon..."
ifeq ($(OS),Darwin)
	@app=""; \
	for cand in /Applications/WezTerm.app $(HOME)/Applications/WezTerm.app; do \
		[ -d "$$cand" ] && app="$$cand" && break; \
	done; \
	if [ -z "$$app" ]; then \
		echo "  ⚠ WezTerm.app not found in /Applications or ~/Applications — skipping"; \
	else \
		set -e; \
		echo "  • target: $$app"; \
		tmp=$$(mktemp -d); iconset="$$tmp/wezterm.iconset"; mkdir -p "$$iconset"; \
		for s in 16 32 128 256 512; do \
			sips -z $$s $$s "$(ICON_SRC)/master-1024.png" --out "$$iconset/icon_$${s}x$${s}.png" >/dev/null; \
			d=$$((s * 2)); \
			sips -z $$d $$d "$(ICON_SRC)/master-1024.png" --out "$$iconset/icon_$${s}x$${s}@2x.png" >/dev/null; \
		done; \
		iconutil -c icns "$$iconset" -o "$$tmp/icon.icns"; \
		res="$$app/Contents/Resources"; \
		icns=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$$app/Contents/Info.plist" 2>/dev/null || echo terminal); \
		case "$$icns" in *.icns) ;; *) icns="$$icns.icns" ;; esac; \
		if [ -f "$$res/$$icns" ] && [ ! -f "$$res/$$icns.orig" ]; then \
			cp "$$res/$$icns" "$$res/$$icns.orig"; \
			echo "  ✓ backed up original -> Contents/Resources/$$icns.orig"; \
		fi; \
		cp "$$tmp/icon.icns" "$$res/$$icns"; \
		rm -rf "$$tmp"; \
		touch "$$app"; killall Dock >/dev/null 2>&1 || true; \
		echo "  ✓ replaced WezTerm.app icon ($$icns)"; \
		echo "  ⚠ editing the signed bundle invalidates its code signature, is reset on the"; \
		echo "    next WezTerm update, and can rarely make macOS flag the app as damaged."; \
		echo "    Restore: cp $$res/$$icns.orig $$res/$$icns"; \
	fi
else
	@hi="$(HOME)/.local/share/icons/hicolor"; \
	for s in 16 24 32 48 64 128 256 512; do \
		mkdir -p "$$hi/$${s}x$${s}/apps"; \
		cp "$(ICON_SRC)/hicolor/$${s}x$${s}/apps/$(ICON_NAME).png" "$$hi/$${s}x$${s}/apps/$(ICON_NAME).png"; \
	done; \
	echo "  ✓ icons -> $$hi/<size>/apps/$(ICON_NAME).png"; \
	gtk-update-icon-cache -f -t "$$hi" >/dev/null 2>&1 || true; \
	kbuildsycoca6 >/dev/null 2>&1 || kbuildsycoca5 >/dev/null 2>&1 || true; \
	echo "  ✓ refreshed icon caches (log out/in if the launcher hasn't updated)"
endif

# Provision the Python side of the Neovim Jupyter stack (molten-nvim). Standalone
# like setup-lmstudio: a venv + scientific stack shouldn't run on every install.
# Run this BEFORE first launching nvim so molten's :UpdateRemotePlugins can find pynvim.
setup-jupyter:
	@./scripts/setup-jupyter.sh

# Download/configure the right Qwen2.5-Coder-7B quant for this host's GPU and wire
# up LM Studio for pi. Standalone: a multi-GB model download shouldn't run on every
# install. See scripts/setup-lmstudio.sh for the per-host quant reasoning.
setup-lmstudio:
	@./scripts/setup-lmstudio.sh

# Tune the whole local-LLM stack (LM Studio quant + MU_NUM_CTX + pi model) to this
# machine's GPU in one pass. Writes per-host overrides to ~/.zshrc.local; leaves the
# committed, cross-machine dotfiles untouched. Re-run after a hardware change.
setup-host:
	@./scripts/setup-host.sh

install-skills:
	@echo "Installing pi skills..."
	@if [ -d pi/agent/skills ] && [ -n "$$(ls -A pi/agent/skills 2>/dev/null)" ]; then \
		mkdir -p $(HOME)/.pi/agent/skills; \
		for skill in pi/agent/skills/*/; do \
			name=$$(basename "$$skill"); \
			mkdir -p "$(HOME)/.pi/agent/skills/$$name"; \
			cp "$$skill/SKILL.md" "$(HOME)/.pi/agent/skills/$$name/SKILL.md"; \
			echo "  ✓ $$name"; \
		done; \
	else \
		echo "  – no skills to install (pi/agent/skills/ is empty)"; \
	fi

