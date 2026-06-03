.PHONY: install install-nvim install-pi install-skills deps deps-arch deps-debian deps-ubuntu deps-macos

OS := $(shell uname -s)

install: deps install-nvim install-pi

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

install-pi: install-skills
	@echo "Installing pi agent config..."
	@mkdir -p $(HOME)/.pi/agent
	@cp pi/agent/models.json $(HOME)/.pi/agent/models.json
	@cp pi/agent/settings.json $(HOME)/.pi/agent/settings.json
	@echo "  ✓ models.json"
	@echo "  ✓ settings.json"

install-skills:
	@echo "Installing pi skills..."
	@mkdir -p $(HOME)/.pi/agent/skills
	@for skill in pi/agent/skills/*/; do \
		name=$$(basename "$$skill"); \
		mkdir -p "$(HOME)/.pi/agent/skills/$$name"; \
		cp "$$skill/SKILL.md" "$(HOME)/.pi/agent/skills/$$name/SKILL.md"; \
		echo "  ✓ $$name"; \
	done

