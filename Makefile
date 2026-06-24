.PHONY: install install-nvim install-zsh install-mc install-pi install-fonts install-wezterm-icon setup-jupyter setup-lmstudio setup-host deps deps-arch deps-debian deps-ubuntu deps-macos

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
	brew install git neovim pi
	brew install --cask wezterm lm-studio font-terminess-ttf-nerd-font

deps-arch:
	sudo pacman -Syu --needed git neovim wezterm
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

install-pi:
	@echo "Installing pi agent config..."
	@if [ -L $(HOME)/.pi ]; then \
		echo "  ✓ ~/.pi already symlinked"; \
	elif [ -e $(HOME)/.pi ]; then \
		echo "  ⚠ ~/.pi exists but is not a symlink — skipping"; \
	else \
		ln -s $(CURDIR)/pi $(HOME)/.pi; \
		echo "  ✓ ~/.pi -> $(CURDIR)/pi"; \
	fi
	@if [ -e $(CURDIR)/pi/agent/settings.json ]; then \
		echo "  ✓ pi/agent/settings.json present (host-managed)"; \
	else \
		cp $(CURDIR)/pi/agent/settings.json.template $(CURDIR)/pi/agent/settings.json; \
		echo "  ✓ seeded pi/agent/settings.json from template (run 'make setup-host' to set the model)"; \
	fi

FONT_DIR := $(HOME)/.local/share/fonts
HACK_NERD_URL := https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.tar.xz

install-fonts:
	@echo "Installing Hack Nerd Font..."
ifeq ($(OS),Darwin)
	@if fc-list 2>/dev/null | grep -qi "Hack Nerd Font"; then \
		echo "  ✓ Hack Nerd Font already installed"; \
	else \
		brew install --cask font-hack-nerd-font; \
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
endif

# Replace WezTerm's app icon with the classic Happy Mac (assets/happy-mac.svg).
# Renders a crisp master from the SVG, then installs PNGs into the per-user
# hicolor theme, which XDG searches before /usr/share — so the packaged icon is
# overridden without touching the WezTerm install. Linux only (macOS ships the
# icon inside the .app bundle). Needs rsvg-convert + ImageMagick.
ICON_NAME := org.wezfurlong.wezterm
ICON_DIR  := $(HOME)/.local/share/icons/hicolor
ICON_SIZES := 16 24 32 48 64 96 128 256

install-wezterm-icon:
ifeq ($(OS),Darwin)
	@echo "  ⚠ macOS keeps the icon in WezTerm.app — skipping (Linux only)"
else
	@command -v rsvg-convert >/dev/null 2>&1 || { echo "  ✗ rsvg-convert not found (install librsvg)"; exit 1; }
	@command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1 || { echo "  ✗ ImageMagick not found"; exit 1; }
	@echo "Installing Happy Mac icon for WezTerm..."
	@tmp=$$(mktemp -d) && \
	rsvg-convert -w 512 -h 512 "$(CURDIR)/assets/happy-mac.svg" -o "$$tmp/master.png" && \
	for s in $(ICON_SIZES); do \
		dir="$(ICON_DIR)/$${s}x$${s}/apps" && mkdir -p "$$dir" && \
		( command -v magick >/dev/null 2>&1 && magick "$$tmp/master.png" -filter Lanczos -resize $${s}x$${s} "$$dir/$(ICON_NAME).png" \
		  || convert "$$tmp/master.png" -filter Lanczos -resize $${s}x$${s} "$$dir/$(ICON_NAME).png" ) && \
		echo "  ✓ $${s}x$${s} -> $$dir/$(ICON_NAME).png"; \
	done && \
	rm -rf "$$tmp"
	@gtk-update-icon-cache -f -t "$(ICON_DIR)" >/dev/null 2>&1 || true
	@echo "  ✓ done — restart WezTerm to see the new icon"
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
# machine's GPU in one pass. Writes per-host overrides to ~/.zshrc.mu; leaves the
# committed, cross-machine dotfiles untouched. Re-run after a hardware change.
setup-host:
	@./scripts/setup-host.sh

