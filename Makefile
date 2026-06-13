.PHONY: install install-nvim install-zsh install-mc install-pi install-skills install-fonts deps deps-arch deps-debian deps-ubuntu deps-macos

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

install-skills:
	@echo "Installing pi skills..."
	@mkdir -p $(HOME)/.pi/agent/skills
	@for skill in pi/agent/skills/*/; do \
		name=$$(basename "$$skill"); \
		mkdir -p "$(HOME)/.pi/agent/skills/$$name"; \
		cp "$$skill/SKILL.md" "$(HOME)/.pi/agent/skills/$$name/SKILL.md"; \
		echo "  ✓ $$name"; \
	done

