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

# Package lists to install. Packages that are os flavor spesific can be distinguished by adding ":<os flavor>" at the end of the package name. Accaptable flavor values are: ubuntu, kubuntu
packages_apt_pre=(
    "flameshot"
    "flatpak"
    "gnome-software-plugin-flatpak:ubuntu"
    "kde-config-flatpak:kubuntu"
    "curl"
    "simple-scan"
    "vlc"
    "libreoffice"
)
packages_apt_post=(
    "brave-browser"
)
packages_flatpak=(
    "com.rustdesk.RustDesk"
)


# State the preferred way to install applications not in the apt repository. Acceptable value is either: flatpak or deb
installPreference="flatpak"

prompt_user_config() {
    echo ""
    echo "Detected OS Flavor: $OS_FLAVOR"
    while true; do
        read -rp "Is this the correct OS flavor? Press [Enter] to confirm or type [ubuntu|kubuntu] to override: " input
        if [[ -z "$input" ]]; then
            break
        elif [[ "$input" =~ ^(ubuntu|kubuntu)$ ]]; then
            OS_FLAVOR="$input"
            break
        else
            echo "Invalid input. Please enter 'ubuntu' or 'kubuntu', or press Enter."
        fi
    done

    echo "Default installation method for non apt packages is: $installPreference"
    while true; do
        read -rp "Is this the preferred method? Press [Enter] to confirm or type [flatpak|deb] to override: " input
        if [[ -z "$input" ]]; then
            break
        elif [[ "$input" =~ ^(flatpak|deb)$ ]]; then
            installPreference="$input"
            break
        else
            echo "Invalid input. Please enter 'flatpak' or 'deb', or press Enter."
        fi
    done

    echo ""
    log "CONFIG" "Final OS Flavor: $OS_FLAVOR"
    log "CONFIG" "Final Install Method: $installPreference"
}

detect_os_flavor() {
    if [[ "$XDG_CURRENT_DESKTOP" =~ KDE ]]; then
        echo "kubuntu"
    elif [[ "$XDG_CURRENT_DESKTOP" =~ GNOME ]]; then
        echo "ubuntu"
    elif dpkg -l | grep -q plasma-desktop; then
        echo "kubuntu"
    elif dpkg -l | grep -q gnome-shell; then
        echo "ubuntu"
    else
        echo "unknown"
    fi
}

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

install_rustdesk_github() {
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

install_apt_packages() {
    local list=("$@")
    for pkg_entry in "${list[@]}"; do
        pkg="${pkg_entry%%:*}"
        tag="${pkg_entry##*:}"

        if [[ "$pkg_entry" == "$pkg" || "$tag" == "$OS_FLAVOR" ]]; then
            log "INSTALL" "Installing apt: $pkg"
            apt-get install -y "$pkg" || log "WARN" "Failed to install $pkg"
        else
            log "SKIP" "Skipping $pkg (tagged for $tag)"
        fi
    done
}

install_flatpak_packages() {
    local list=("$@")
    for pkg in "${list[@]}"; do
        log "INSTALL" "Installing flatpak: $pkg"
        flatpak install -y flathub "$pkg" || log "WARN" "Failed to install $pkg"
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
    OS_FLAVOR=$(detect_os_flavor)
    prompt_user_config

    log "APT" "Updating package lists..."
    apt-get update

    install_apt_packages "${packages_apt_pre[@]}"
    add_flathub_repo
    add_brave_repo

    log "APT" "Updating package lists after adding repos..."
    apt-get update

    install_apt_packages "${packages_apt_post[@]}"

    case "$installPreference" in
        flatpak)
            install_flatpak_packages "${packages_flatpak[@]}"
            ;;

        deb)
            install_rustdesk_github || log "WARN" "RustDesk install failed"
            ;;

        *)
            log "ERROR" "No flatpak or deb packages installed because of incorrect value of 'installPreference'. Usage: [flatpak|deb] - Value set: $0"
            exit 1
            ;;
        esac

    install_appimagelauncher_github || log "WARN" "AppImageLauncher install failed"

    if systemd-detect-virt -q; then
        log "ENV" "Running inside a VM ($(systemd-detect-virt)) — skipping GPU driver installation"
    else
        detect_and_install_gpu_driver
    fi

    log "DONE" "Post-installation script completed"
}

main "$@"
