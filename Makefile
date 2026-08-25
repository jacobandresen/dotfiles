.PHONY: install install-nvim install-zsh install-mc install-pi install-ollama install-docker install-fonts setup-host deps deps-arch deps-debian deps-ubuntu deps-macos

OS := $(shell uname -s)

install: deps install-nvim install-zsh install-mc install-ollama install-docker install-pi

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
	brew install --cask ollama font-terminess-ttf-nerd-font

deps-arch:
	sudo pacman -Syu --needed git neovim
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
	@echo "Installing Ollama..."
	@curl -fsSL https://ollama.com/install.sh | sh
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
	@echo "Installing Ollama..."
	@curl -fsSL https://ollama.com/install.sh | sh
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
	@if command -v ollama >/dev/null 2>&1; then \
		model=$$($(CURDIR)/scripts/select-coding-model.sh); \
		profile=$$($(CURDIR)/scripts/detect-ram-profile.sh); \
		echo "  → RAM profile: $$profile → coding model: $$model"; \
		if ollama list | awk 'NR>1{print $$1}' | grep -qx "$$model"; then \
			echo "  ✓ $$model already pulled"; \
		else \
			echo "  ↓ pulling $$model (this may take a while)..."; \
			ollama pull "$$model"; \
		fi; \
		echo "  ⏳ loading $$model into memory..."; \
		curl -s http://127.0.0.1:11434/api/generate -d "{\"model\":\"$$model\",\"prompt\":\"hi\",\"stream\":false}" >/dev/null; \
		echo "  ✓ $$model loaded"; \
		$(CURDIR)/scripts/setup-host.sh; \
	else \
		echo "  ⚠ ollama not found — skipping model selection (run 'make deps' first)"; \
	fi

install-ollama:
	@echo "Installing Ollama systemd overrides..."
ifeq ($(OS),Linux)
	@profile=$$($(CURDIR)/scripts/detect-ram-profile.sh); \
	echo "  → detected RAM profile: $$profile"; \
	sudo mkdir -p /etc/systemd/system/ollama.service.d; \
	sudo cp $(CURDIR)/ollama/ollama.service.d/override-$$profile.conf /etc/systemd/system/ollama.service.d/override.conf; \
	sudo systemctl daemon-reload; \
	sudo systemctl restart ollama; \
	echo "  ✓ /etc/systemd/system/ollama.service.d/override.conf installed ($$profile profile) and ollama restarted"
else
	@echo "  ⚠ skipping (not Linux/systemd)"
endif

install-docker:
	@echo "Installing Docker systemd overrides..."
ifeq ($(OS),Linux)
	@if ! command -v docker >/dev/null 2>&1 && ! systemctl list-unit-files docker.service >/dev/null 2>&1; then \
		echo "  ⚠ Docker not found — skipping (install it first)"; \
	else \
		profile=$$($(CURDIR)/scripts/detect-ram-profile.sh); \
		echo "  → detected RAM profile: $$profile"; \
		sudo mkdir -p /etc/systemd/system/docker.service.d; \
		sudo cp $(CURDIR)/docker/docker.service.d/override-$$profile.conf /etc/systemd/system/docker.service.d/override.conf; \
		sudo systemctl daemon-reload; \
		sudo systemctl restart docker; \
		echo "  ✓ /etc/systemd/system/docker.service.d/override.conf installed ($$profile profile) and docker restarted"; \
	fi
else
	@echo "  ⚠ skipping (not Linux/systemd)"
endif

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

# Point pi agent at whatever model Ollama currently has loaded on this
# machine, host-managed so the committed, cross-machine dotfiles stay
# untouched. Re-run after switching models or a hardware change. (mu tunes
# itself — see `make setup-host` in the mu repo.)
setup-host:
	@./scripts/setup-host.sh

