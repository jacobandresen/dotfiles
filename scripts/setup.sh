#!/bin/sh
set -e

IS_WSL=0
case "$(uname -r)" in *microsoft* | *Microsoft*) IS_WSL=1 ;; esac

if [ "$(uname)" = "Darwin" ]; then
  brew install neovim make gcc node python jq git fpc fzf ripgrep fd ollama sonar-scanner openjdk@17
  brew install --cask font-terminess-ttf-nerd-font
elif [ -f /etc/arch-release ]; then
  sudo pacman -S --needed neovim ttf-terminus-nerd base-devel make gcc nodejs npm python jq git fpc fzf wl-clipboard ripgrep fd ollama jre17-openjdk unzip
elif [ -f /etc/debian_version ]; then
  sudo apt-get update
  # The apt neovim is often outdated; use the upstream PPA for a recent stable release
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:neovim-ppa/stable
  sudo apt-get update
  sudo apt-get install -y neovim build-essential make gcc nodejs npm python3 jq git fpc fzf ripgrep fd-find openjdk-17-jre-headless unzip
  # fd-find ships the binary as 'fdfind'; symlink to 'fd' so tools can find it
  if command -v fdfind > /dev/null 2>&1 && [ ! -e /usr/local/bin/fd ]; then
    sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
  fi
  # ollama — official install script (covers x86-64 and arm64)
  echo "Downloading ollama installer..."
  curl -fL# https://ollama.com/install.sh | sh
  if [ "$IS_WSL" = "1" ]; then
    echo "Note: install Terminess Nerd Font on your Windows host (not inside WSL)."
    echo "Download TerminessTTF from https://www.nerdfonts.com/font-downloads and install via Windows Font Settings."
  else
    echo "Note: install Terminess Nerd Font manually."
    echo "Download TerminessTTF from https://www.nerdfonts.com/font-downloads"
  fi
else
  echo "Unsupported OS" >&2
  exit 1
fi

# ── SonarQube CE + sonar-scanner (Linux only; macOS gets scanner via brew) ──
# Update these versions by checking https://www.sonarsource.com/products/sonarqube/downloads/
SONARQUBE_VERSION="26.4.0.121862"
SCANNER_VERSION="8.1.0.6389"
# Update this plugin version to match your SonarQube release:
# https://github.com/SonarOpenCommunity/sonar-cxx/releases
SONAR_CXX_TAG="2.2.2"
SONAR_CXX_VERSION="2.2.2.1409"

if [ "$(uname)" != "Darwin" ]; then
  # sonar-scanner CLI
  if ! command -v sonar-scanner > /dev/null 2>&1; then
    SCANNER_DIR="sonar-scanner-${SCANNER_VERSION}-linux-x64"
    echo "Downloading sonar-scanner ${SCANNER_VERSION}..."
    curl -fL# \
      "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SCANNER_VERSION}-linux-x64.zip" \
      -o /tmp/sonar-scanner.zip
    sudo unzip -q /tmp/sonar-scanner.zip -d /opt
    sudo mv "/opt/${SCANNER_DIR}" /opt/sonar-scanner
    sudo ln -sf /opt/sonar-scanner/bin/sonar-scanner /usr/local/bin/sonar-scanner
    rm -f /tmp/sonar-scanner.zip
  fi

  # SonarQube CE server (started on-demand, not as a system service)
  if [ ! -d /opt/sonarqube ]; then
    echo "Downloading SonarQube CE ${SONARQUBE_VERSION}..."
    curl -fL# \
      "https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_VERSION}.zip" \
      -o /tmp/sonarqube.zip
    sudo unzip -q /tmp/sonarqube.zip -d /opt
    sudo mv "/opt/sonarqube-${SONARQUBE_VERSION}" /opt/sonarqube
    rm -f /tmp/sonarqube.zip

    # sonar-cxx plugin — C/C++ analysis for Community Edition
    sudo mkdir -p /opt/sonarqube/extensions/plugins
    echo "Downloading sonar-cxx plugin ${SONAR_CXX_VERSION}..."
    curl -fL# \
      "https://github.com/SonarOpenCommunity/sonar-cxx/releases/download/cxx-${SONAR_CXX_TAG}/sonar-cxx-plugin-${SONAR_CXX_VERSION}.jar" \
      -o /tmp/sonar-cxx-plugin.jar
    sudo mv /tmp/sonar-cxx-plugin.jar /opt/sonarqube/extensions/plugins/
  fi
fi

# AI backend — installed via npm on all platforms
npm install -g @earendil-works/pi-coding-agent

# Pull the default local model (ollama auto-starts its server if needed)
ollama pull gemma4
