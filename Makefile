.PHONY: install deps doctor ram-profile use-model install-mellum verify-model
.PHONY: install-nvim install-zsh install-mc install-kitty install-pi install-workflow update-pi install-ollama install-docker install-fonts
.PHONY: deps-arch deps-compose deps-debian deps-ubuntu deps-macos deps-docker-macos deps-common

OS := $(shell uname -s)
PYTHON ?= python3
CLI := $(PYTHON) "$(CURDIR)/scripts/dotfiles.py"
DISTRO_ID := $(shell . /etc/os-release 2>/dev/null && echo $$ID)

install: deps
	@$(MAKE) install-nvim install-zsh install-mc install-kitty install-workflow
	@$(MAKE) install-ollama
	@$(MAKE) install-docker
	@$(MAKE) install-mellum

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
	@$(MAKE) install-fonts

deps-macos:
	@$(CLI) install-homebrew
	brew install git neovim lazydocker lazygit luarocks imagemagick tectonic ripgrep fd jq make pkgconf node python zsh midnight-commander coreutils
	brew install --cask ollama kitty font-hack-nerd-font
	npm install --global tree-sitter-cli @mermaid-js/mermaid-cli
	@$(MAKE) deps-common
	@echo "Docker Desktop is optional: make deps-docker-macos"

deps-docker-macos:
	@if [ -d /Applications/Docker.app ]; then \
		echo "  ✓ Docker Desktop already installed"; \
	else \
		brew install --cask docker; \
	fi
	@$(MAKE) install-docker

deps-common:
	@$(CLI) install-cli-tools

deps-arch:
	sudo pacman -Syu --needed git neovim curl python zsh ripgrep fd jq base-devel pkgconf nodejs npm unzip fontconfig kitty mc lazydocker lazygit luarocks imagemagick texlive docker docker-compose zstd wl-clipboard xclip
	sudo npm install --global tree-sitter-cli @mermaid-js/mermaid-cli
	@$(MAKE) deps-common

deps-ubuntu deps-debian:
	sudo apt-get update
	sudo apt-get install -y git curl python3 zsh ripgrep fd-find jq build-essential pkg-config nodejs npm unzip fontconfig kitty mc docker.io zstd lazygit luarocks imagemagick texlive-latex-base wl-clipboard xclip
	sudo npm install --global tree-sitter-cli @mermaid-js/mermaid-cli
	@$(CLI) install-neovim
	@$(MAKE) --no-print-directory deps-compose
	@$(MAKE) deps-common

deps-compose:
	@$(CLI) install-compose

install-nvim:
	@$(CLI) install-link skip "$(CURDIR)/nvim" "$(HOME)/.config/nvim"

install-zsh:
	@$(CLI) install-link backup "$(CURDIR)/.zshrc" "$(HOME)/.zshrc"

install-mc:
	@$(CLI) install-link backup "$(CURDIR)/mc/ini" "$(HOME)/.config/mc/ini"
	@mkdir -p $(HOME)/.local/share/mc/skins
	@for skin in retrobox turbopascal; do \
		ln -sfn $(CURDIR)/mc/skins/$$skin.ini $(HOME)/.local/share/mc/skins/$$skin.ini; \
		echo "  ✓ ~/.local/share/mc/skins/$$skin.ini -> $(CURDIR)/mc/skins/$$skin.ini"; \
	done

install-kitty:
	@$(CLI) install-link backup "$(CURDIR)/kitty" "$(HOME)/.config/kitty"
	@if [ "$(OS)" = "Linux" ]; then \
		$(CLI) install-link backup "$(CURDIR)/kitty/dos-kitty.svg" "$(HOME)/.local/share/icons/hicolor/scalable/apps/kitty.svg"; \
	fi

install-pi:
	@$(PYTHON) ./scripts/pi_config.py

install-workflow:
	@mkdir -p "$(HOME)/.local/bin"
	@ln -sfn "$(CURDIR)/scripts/git-pi" "$(HOME)/.local/bin/git-pi"
	@echo "  ✓ ~/.local/bin/git-pi -> $(CURDIR)/scripts/git-pi"

update-pi:
	@pi update --all

install-ollama:
	@$(CLI) install-ollama

use-model:
	@$(CLI) use-model

install-mellum:
	@$(MAKE) use-model

install-docker:
	@$(CLI) install-docker

install-fonts:
	@$(CLI) install-fonts

verify-model:
	@$(CLI) verify-model

ram-profile:
	@$(CLI) show-profile

doctor:
	@$(CLI) doctor

