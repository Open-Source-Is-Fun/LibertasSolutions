#!/bin/bash

### Post (K)Ubuntu Install Script ###

LOGFILE="/var/log/postinstall.log"
exec > >(tee -a "$LOGFILE") 2>&1

timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

log() {
    echo "[$(timestamp)] [$1] $2"
}

# Exit on critical error
set -e

# Check if script is run with sudo privileges
if [[ $EUID -ne 0 ]]; then
    log "ERROR" "This script must be run as root."
    exit 1
fi

log "START" "Post-installation script started"

# Package lists to install
packages_pre=(
    "flameshot"
    "flatpak"
    "gnome-software-plugin-flatpak"
    "curl"
    "simple-scan"
    "vlc"
    "libreoffice"
)
packages_post=(
    "brave-browser"
)

add_brave_repo() {
    log "REPO" "Adding Brave browser repository"
    curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
        https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg || {
        log "ERROR" "Failed to download Brave GPG key"
        exit 1
    }

    curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources \
        https://brave-browser-apt-release.s3.brave.com/brave-browser.sources || {
        log "ERROR" "Failed to add Brave source list"
        exit 1
    }
}

add_flathub_repo() {
    log "REPO" "Adding Flathub repository"
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || {
        log "WARN" "Failed to add Flathub repo (possibly already added)"
    }
}

install_appimagelauncher_github() {
    log "INSTALL" "Installing latest AppImageLauncher release"
    url=$(curl -s https://api.github.com/repos/TheAssassin/AppImageLauncher/releases/latest \
        | grep "browser_download_url.*bionic.*amd64.deb" \
        | cut -d '"' -f 4 | head -n 1)

    echo $url
    if [[ -z $url ]]; then
        echo "ERROR" "Could not find AppImageLauncher .deb URL"
        return 1
    fi

    file=$(basename "$url")
    log "DOWNLOAD" "Downloading $file"
    wget -O "$file" "$url" || return 1

    log "INSTALL" "Installing $file"
    apt-get install -y ./"$file" || return 1
    rm -f "$file"
}

install_rustdesk() {
    log "INSTALL" "Installing latest RustDesk release"
    url=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
        | grep "browser_download_url.*x86_64.deb" \
        | cut -d '"' -f 4)

    if [[ -z $url ]]; then
        log "ERROR" "Could not find RustDesk .deb URL"
        return 1
    fi

    file=$(basename "$url")
    log "DOWNLOAD" "Downloading $file"
    wget -O "$file" "$url" || return 1

    log "INSTALL" "Installing $file"
    apt-get install -y ./"$file" || return 1
    rm -f "$file"
}

install_packages() {
    local list=("$@")
    for pkg in "${list[@]}"; do
        log "INSTALL" "Installing $pkg"
        apt-get install -y "$pkg" || log "WARN" "Failed to install $pkg"
    done
}

detect_and_install_gpu_driver() {
    log "GPU" "Detecting graphics driver..."
    GPU_INFO=$(lspci | grep -i 'vga\|3d\|2d')
    log "GPU" "Detected GPU: $GPU_INFO"

    if [[ $GPU_INFO == *"NVIDIA"* ]]; then
        log "GPU" "NVIDIA GPU detected"
        apt-get install -y ubuntu-drivers-common
        log "GPU" "Running ubuntu-drivers autoinstall"
        ubuntu-drivers autoinstall
    elif [[ $GPU_INFO == *"AMD"* ]] || [[ $GPU_INFO == *"ATI"* ]]; then
        log "GPU" "AMD GPU detected"
        apt-get install -y mesa-utils
    elif [[ $GPU_INFO == *"Intel"* ]]; then
        log "GPU" "Intel GPU detected"
        apt-get install -y mesa-utils
    else
        log "GPU" "Unknown GPU vendor: $GPU_INFO"
    fi
}

main() {
    log "APT" "Updating package lists..."
    apt-get update

    install_packages "${packages_pre[@]}"
    add_flathub_repo
    add_brave_repo

    log "APT" "Updating package lists after adding repos..."
    apt-get update

    install_packages "${packages_post[@]}"
    install_appimagelauncher_github || log "WARN" "AppImageLauncher install failed"
    install_rustdesk || log "WARN" "RustDesk install failed"

    if systemd-detect-virt -q; then
        log "ENV" "Running inside a VM ($(systemd-detect-virt)) — skipping GPU driver installation"
    else
        detect_and_install_gpu_driver
    fi

    log "DONE" "Post-installation script completed"
}

main "$@"
