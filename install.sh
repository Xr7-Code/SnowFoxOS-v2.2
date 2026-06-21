#!/bin/bash
# ============================================================
#  SnowFoxOS v2.1 — Installer
#  Basis: Debian 12 (Bookworm) minimal
#  Desktop: i3 + Polybar + Rofi + Dunst + i3lock
#  Ausführen: sudo bash install.sh
# ============================================================

PURPLE='\033[0;35m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;37m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${PURPLE}${BOLD}[SnowFox]${RESET} $1"; }
success() { echo -e "${GREEN}${BOLD}[  OK  ]${RESET} $1"; }
warn()    { echo -e "${ORANGE}${BOLD}[ WARN ]${RESET} $1"; }
error()   { echo -e "${RED}${BOLD}[FEHLER]${RESET} $1"; exit 1; }
step()    { echo -e "\n${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}";
            echo -e "${PURPLE}${BOLD}  $1${RESET}";
            echo -e "${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"; }

ask_install() {
    echo ""
    read -rp "$(echo -e ${PURPLE}${BOLD}"[SnowFox] $1 installieren? [j/n]: "${RESET})" choice
    [[ "$choice" =~ ^[jJ]$ ]]
}

wait_apt() {
    local i=0
    while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock > /dev/null 2>&1; do
        [[ $i -eq 0 ]] && info "Warte auf apt-Lock..."
        sleep 2; i=$((i+1))
        [[ $i -gt 60 ]] && error "apt-Lock nach 120s nicht frei"
    done
}

# ── Root-Check ───────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Bitte mit sudo ausführen: sudo bash install.sh"
fi

# ── Debian 12 Validierung ────────────────────────────────────
if [[ ! -f /etc/debian_version ]] || ! grep -q "^12\." /etc/debian_version; then
    warn "Dieses Script ist für Debian 12 (Bookworm) optimiert."
fi

# ── Benutzer ermitteln ───────────────────────────────────────
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    read -rp "Benutzername: " TARGET_USER
fi
TARGET_HOME="/home/$TARGET_USER"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ ! -d "$TARGET_HOME" ]] && error "Home $TARGET_HOME nicht gefunden"

info "Installiere für: ${BOLD}$TARGET_USER${RESET}"
sleep 1

# ============================================================
# SCHRITT 1 — System & Repositories
# ============================================================
step "1/10 — System aktualisieren"

# DKMS-Hooks temporär deaktivieren
DKMS_HOOKS=(
    /etc/kernel/postinst.d/dkms
    /etc/kernel/prerm.d/dkms
    /usr/lib/kernel/install.d/50-dkms.install
)
for hook in "${DKMS_HOOKS[@]}"; do
    [[ -f "$hook" ]] && mv "$hook" "${hook}.snowfox-bak"
done
info "DKMS-Hooks für Installer-Lauf deaktiviert"

# apt-daily deaktivieren — verhindert Boot-Verzögerungen und Lock-Konflikte
systemctl disable apt-daily.service apt-daily.timer 2>/dev/null || true
systemctl disable apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true
systemctl stop apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
success "apt-daily deaktiviert"

cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
EOF

wait_apt
dpkg --add-architecture i386
apt-get update -qq
dpkg --configure -a 2>/dev/null || true
apt-get -f install -y 2>/dev/null || true
wait_apt
apt-get upgrade -y
apt-get install -y \
    curl wget git unzip \
    build-essential \
    ca-certificates \
    aria2 \
    fzf \
    lz4 \
    gnupg \
    pciutils usbutils \
    htop btop neofetch irqbalance \
    bash-completion \
    xdg-utils \
    xdg-user-dirs \
    rfkill \
    iw wireless-tools \
    imagemagick \
    bc \
    xorg \
    xinit \
    x11-utils \
    x11-xserver-utils \
    xclip \
    xdotool \
    dbus-x11 \
    lm-sensors

sudo -u "$TARGET_USER" xdg-user-dirs-update
success "System aktualisiert"

# ── XanMod Kernel ────────────────────────────────────────────
info "Prüfe CPU-Kompatibilität für x64v3..."
if ! grep -q "avx2" /proc/cpuinfo; then
    error "CPU unterstützt kein AVX2 — Installation abgebrochen um System-Brick zu verhindern."
fi

info "Installiere DKMS-Tools..."
apt-get install -y --no-install-recommends dkms libdw-dev clang lld llvm
success "DKMS-Tools installiert"

info "Installiere XanMod LTS Kernel..."
dpkg --configure -a 2>/dev/null || true
apt-get -f install -y 2>/dev/null || true

mkdir -p /etc/apt/keyrings
wget -qO - https://dl.xanmod.org/archive.key \
    | gpg --dearmor --yes -o /etc/apt/keyrings/xanmod-archive-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org bookworm main" \
    > /etc/apt/sources.list.d/xanmod-release.list

wait_apt
apt-get update -qq
wait_apt

DEBIAN_FRONTEND=noninteractive apt-get install -y linux-xanmod-lts-x64v3
XANMOD_EXIT=$?

if [[ $XANMOD_EXIT -eq 0 ]]; then
    success "XanMod LTS Kernel installiert (aktiv nach Reboot)"

    if [[ -f /etc/default/grub ]]; then
        # Kernel-Parameter je nach GPU-Konfiguration
        GRUB_PARAMS="quiet splash"

        if lspci | grep -qi nvidia; then
            GRUB_PARAMS="$GRUB_PARAMS nvidia-drm.modeset=1"
        fi

        # AMD+NVIDIA Hybrid: IOMMU aktivieren verhindert DRM Fence Timeout Freezes
        if lspci | grep -qi nvidia && lspci | grep -qi amd; then
            GRUB_PARAMS="$GRUB_PARAMS amd_iommu=on iommu=pt"
            info "AMD+NVIDIA Hybrid erkannt: IOMMU-Parameter gesetzt (verhindert Freezes)"
        fi

        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_PARAMS\"/" /etc/default/grub
        sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
    fi

    # XanMod LTS als Standard setzen
    XANMOD_VER=$(ls /lib/modules 2>/dev/null | grep xanmod-lts 2>/dev/null | sort -V | tail -1)
    if [[ -n "$XANMOD_VER" ]]; then
        grub-set-default "Advanced options for SnowFoxOS GNU/Linux>SnowFoxOS GNU/Linux, with Linux $XANMOD_VER" 2>/dev/null || true
    fi

    update-grub 2>/dev/null || true
    success "Boot-Konfiguration aktualisiert"
else
    warn "XanMod fehlgeschlagen (Exit $XANMOD_EXIT) — Installation wird fortgesetzt"
fi

# Fritz USB AC 860 Treiber
apt-get install -y firmware-misc-nonfree 2>/dev/null || true
if lsusb 2>/dev/null | grep -qi "fritz\|0x0bda\|2357"; then
    modprobe mt76x2u 2>/dev/null && \
        success "Fritz USB AC 860 Treiber geladen" || \
        warn "Fritz USB Treiber nicht gefunden — nach Reboot prüfen"
fi

# USB-WLAN Power-Management deaktiviert lassen — verhindert hängende
# Verbindungen bei USB-WLAN-Adaptern (z.B. Fritz AC 860) durch Autosuspend
cat > /etc/udev/rules.d/70-usb-wlan-power.rules << 'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="057c", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", DRIVER=="mt76x2u", ATTR{power/control}="on"
EOF
success "USB-WLAN Autosuspend-Fix installiert"

# RTL8821CE (HP-Laptops u.a.) — bekannter Stromspar-Bug der Verbindungen
# instabil macht / DHCP fehlschlagen lässt. Fix: tiefen Stromsparmodus
# und ASPM für diesen Chip deaktivieren.
if lspci -k 2>/dev/null | grep -qi "RTL8821CE"; then
    info "RTL8821CE WLAN-Chip erkannt — wende Stabilitäts-Fix an..."
    cat > /etc/modprobe.d/rtw88.conf << 'EOF'
options rtw88_core disable_lps_deep=y
options rtw88_pci disable_aspm=y
EOF
    success "RTL8821CE Stabilitäts-Fix installiert (disable_lps_deep, disable_aspm)"
fi

# ============================================================
# SCHRITT 2 — Hardware-Erkennung & Treiber
# ============================================================
step "2/10 — Hardware-Analyse & Treiber"

IS_LAPTOP=false
[[ "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" =~ ^(8|9|10|14)$ ]] && IS_LAPTOP=true

CPU_INFO=$(grep -m1 "vendor_id" /proc/cpuinfo)
if echo "$CPU_INFO" | grep -qi "AuthenticAMD"; then
    apt-get install -y amd64-microcode
    success "AMD CPU Microcode installiert"
else
    apt-get install -y intel-microcode
    success "Intel CPU Microcode installiert"
fi

GPU_INFO=$(lspci | grep -iE 'vga|3d|display')
HAS_NVIDIA=false
HAS_AMD=false
HAS_INTEL=false
echo "$GPU_INFO" | grep -qi "nvidia" && HAS_NVIDIA=true
echo "$GPU_INFO" | grep -qi "amd"    && HAS_AMD=true
echo "$GPU_INFO" | grep -qi "intel"  && HAS_INTEL=true

if $HAS_NVIDIA; then
    info "NVIDIA GPU erkannt — Installiere Treiber via CUDA-Repo..."

    apt-get install -y clang-19 lld-19 2>/dev/null || apt-get install -y clang lld || true
    update-alternatives --install /usr/bin/clang   clang   /usr/bin/clang-19  100 2>/dev/null || true
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-19 100 2>/dev/null || true
    update-alternatives --install /usr/bin/lld     lld     /usr/bin/lld-19    100 2>/dev/null || true
    update-alternatives --install /usr/bin/ld.lld  ld.lld  /usr/bin/lld-19    100 2>/dev/null || true
    update-alternatives --set clang  /usr/bin/clang-19  2>/dev/null || true
    update-alternatives --set lld    /usr/bin/lld-19    2>/dev/null || true
    update-alternatives --set ld.lld /usr/bin/lld-19    2>/dev/null || true

    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/3bf863cc.pub \
        | gpg --dearmor | tee /usr/share/keyrings/nvidia-cuda-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/nvidia-cuda-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/ /" \
        | tee /etc/apt/sources.list.d/nvidia-cuda.list

    cat > /etc/apt/preferences.d/nvidia-cuda << 'EOF'
Package: cuda-drivers* nvidia-* libcuda* libnvidia-*
Pin: origin "developer.download.nvidia.com"
Pin-Priority: 900

Package: *
Pin: release o=Debian
Pin-Priority: 500
EOF

    wait_apt
    apt-get update -qq
    apt-get purge -y nvidia-driver nvidia-kernel-dkms 2>/dev/null || true
    wait_apt
    apt-get install -y \
        cuda-drivers-580 \
        libvulkan1 libvulkan1:i386 \
        nvidia-vulkan-icd nvidia-vulkan-icd:i386

    # envycontrol für Hybrid-Systeme (AMD + NVIDIA)
    if $HAS_AMD; then
        info "Hybrid GPU erkannt — Installiere envycontrol..."
        ENVY_DEB_URL=$(curl -sf https://api.github.com/repos/bayasdev/envycontrol/releases/latest 2>/dev/null \
            | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for a in data.get('assets', []):
        if a['name'].endswith('.deb'):
            print(a['browser_download_url'])
            break
except: pass
" 2>/dev/null)
        if [[ -n "$ENVY_DEB_URL" ]]; then
            curl -L "$ENVY_DEB_URL" -o /tmp/envycontrol.deb
            dpkg -i /tmp/envycontrol.deb 2>/dev/null || apt-get -f install -y
            rm -f /tmp/envycontrol.deb
            success "envycontrol installiert"
        else
            # Fallback: pip in venv
            python3 -m venv /opt/envycontrol-venv
            /opt/envycontrol-venv/bin/pip install git+https://github.com/bayasdev/envycontrol.git 2>/dev/null || true
            ln -sf /opt/envycontrol-venv/bin/envycontrol /usr/local/bin/envycontrol
            success "envycontrol installiert (venv)"
        fi

        # Hybrid-Modus als Standard setzen
        envycontrol -s hybrid 2>/dev/null || true
        success "GPU-Modus: hybrid"
    fi

    XANMOD_KERNEL=$(ls /lib/modules 2>/dev/null | grep xanmod | sort -V | tail -1)
    NVIDIA_VER=$(ls /var/lib/dkms/nvidia/ 2>/dev/null | sort -V | tail -1)
    if [[ -n "$XANMOD_KERNEL" && -n "$NVIDIA_VER" ]]; then
        info "Baue NVIDIA DKMS-Module für $XANMOD_KERNEL..."
        dkms install nvidia/"$NVIDIA_VER" -k "$XANMOD_KERNEL" 2>/dev/null || \
            warn "DKMS-Build fehlgeschlagen — nach Reboot prüfen"
        success "NVIDIA DKMS-Module gebaut"
    else
        warn "DKMS übersprungen (Kernel: ${XANMOD_KERNEL:-?}, NVIDIA: ${NVIDIA_VER:-?})"
    fi

    success "NVIDIA Stack installiert"

elif $HAS_AMD; then
    info "AMD GPU erkannt — Nutze Mesa..."
    apt-get install -y firmware-amd-graphics mesa-vulkan-drivers mesa-va-drivers
    success "AMD Stack installiert"

elif $HAS_INTEL; then
    info "Intel Grafik erkannt..."
    apt-get install -y intel-media-va-driver-non-free i965-va-driver 2>/dev/null || true
    success "Intel Stack installiert"
fi

if $IS_LAPTOP; then
    info "Laptop erkannt: Installiere Akku- & Touchpad-Tools..."
    apt-get install -y tlp tlp-rdw thermald xserver-xorg-input-libinput
    systemctl enable tlp thermald
    success "Laptop-Optimierung abgeschlossen"
fi

success "GPU-Treiber eingerichtet"

# ============================================================
# SCHRITT 3 — i3 Desktop
# ============================================================
step "3/10 — i3 + Polybar + Rofi + Dunst + i3lock"

wait_apt
apt-get install -y \
    i3 \
    i3status \
    i3lock \
    polybar \
    rofi \
    dunst \
    libnotify-bin \
    libappindicator3-1 \
    libayatana-appindicator3-1 \
    feh \
    xdg-desktop-portal \
    libdbusmenu-gtk3-4 \
    redshift \
    scrot \
    brightnessctl \
    playerctl \
    network-manager \
    bluez \
    fonts-inter \
    fonts-noto \
    fonts-noto-color-emoji \
    fonts-font-awesome \
    fonts-jetbrains-mono \
    papirus-icon-theme \
    arc-theme \
    qt5ct qt6ct \
    qt5-style-plugins \
    xsettingsd \
    lxpolkit \
    lxappearance \
    picom \
    xss-lock \
    xserver-xorg-input-libinput \
    diodon \
    cups cups-bsd cups-client \
    printer-driver-splix

# bluetui — Terminal Bluetooth Manager (kein blueman/GNOME)
info "Installiere bluetui..."
BLUETUI_URL=$(curl -sf https://api.github.com/repos/pythops/bluetui/releases/latest 2>/dev/null \
    | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for a in data.get('assets', []):
        if 'x86_64' in a['name'] and 'linux' in a['name'] and a['name'].endswith('.tar.gz'):
            print(a['browser_download_url'])
            break
except: pass
" 2>/dev/null)
if [[ -n "$BLUETUI_URL" ]]; then
    curl -L "$BLUETUI_URL" -o /tmp/bluetui.tar.gz
    tar -xzf /tmp/bluetui.tar.gz -C /tmp/
    mv /tmp/bluetui /usr/local/bin/bluetui 2>/dev/null || \
        find /tmp -name "bluetui" -type f -exec mv {} /usr/local/bin/bluetui \;
    chmod +x /usr/local/bin/bluetui
    rm -f /tmp/bluetui.tar.gz
    success "bluetui installiert"
else
    warn "bluetui nicht verfügbar — Bluetooth über 'bluetoothctl' nutzbar"
fi

systemctl enable bluetooth

# Desktop-Einträge — nmtui, bluetui, pcmanfm (für Rofi)
mkdir -p "$TARGET_HOME/.local/share/applications"

cat > "$TARGET_HOME/.local/share/applications/nmtui.desktop" << 'EOF'
[Desktop Entry]
Name=Netzwerk
Comment=Netzwerkverbindungen verwalten (nmtui)
Exec=kitty -e nmtui
Icon=network-wireless
Type=Application
Categories=Network;System;
EOF

cat > "$TARGET_HOME/.local/share/applications/bluetui.desktop" << 'EOF'
[Desktop Entry]
Name=Bluetooth
Comment=Bluetooth-Geräte verwalten (bluetui)
Exec=kitty -e bluetui
Icon=bluetooth
Type=Application
Categories=System;
EOF

cat > "$TARGET_HOME/.local/share/applications/pcmanfm.desktop" << 'EOF'
[Desktop Entry]
Name=Dateien
Comment=Dateimanager
Exec=pcmanfm %U
Icon=system-file-manager
Type=Application
Categories=System;FileManager;
EOF

chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.local/share/applications"
success "Desktop-Einträge für Netzwerk, Bluetooth, Dateien installiert (Rofi-fähig)"

# Touchpad-Config
mkdir -p /etc/X11/xorg.conf.d
if [[ -f "$SCRIPT_DIR/configs/xorg/30-touchpad.conf" ]]; then
    cp "$SCRIPT_DIR/configs/xorg/30-touchpad.conf" /etc/X11/xorg.conf.d/30-touchpad.conf
    info "Touchpad-Config aus Repo kopiert"
else
    cat > /etc/X11/xorg.conf.d/30-touchpad.conf << 'EOF'
Section "InputClass"
    Identifier      "libinput touchpad"
    MatchIsTouchpad "on"
    MatchDevicePath "/dev/input/event*"
    Driver          "libinput"
    Option          "Tapping"            "on"
    Option          "ClickMethod"        "clickfinger"
    Option          "NaturalScrolling"   "true"
    Option          "DisableWhileTyping" "on"
EndSection
EOF
    info "Touchpad-Config erstellt"
fi

# i3 Autostart
BASH_PROFILE="$TARGET_HOME/.bash_profile"
if ! grep -q "startx" "$BASH_PROFILE" 2>/dev/null; then
    echo '' >> "$BASH_PROFILE"
    echo '# SnowFoxOS — i3 automatisch starten' >> "$BASH_PROFILE"
    echo '[ "$(tty)" = "/dev/tty1" ] && exec startx' >> "$BASH_PROFILE"
fi

# xinitrc — kein gsettings, kein kvantum, kein GNOME
cat > "$TARGET_HOME/.xinitrc" << 'EOF'
#!/bin/sh
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games

# Theme
export GTK_THEME=Arc-Dark
export QT_QPA_PLATFORMTHEME=qt5ct
export _JAVA_AWT_WM_NONREPARENTING=1

# xsettingsd für GTK-Theme in X11
xsettingsd &

# DBus
if [ -f /usr/bin/dbus-launch ]; then
    eval $(/usr/bin/dbus-launch --sh-syntax --exit-with-session)
fi

exec i3
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.xinitrc"
chmod +x "$TARGET_HOME/.xinitrc"

success "i3 Desktop & Autostart eingerichtet"
# ── Nerd Fonts ───────────────────────────────────────────────
info "Installiere Nerd Fonts (JetBrainsMono)..."
NERD_VERSION=$(curl -sf https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','v3.2.1'))" 2>/dev/null || echo "v3.2.1")
NERD_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_VERSION}/JetBrainsMono.zip"
mkdir -p /usr/local/share/fonts/nerd-fonts
curl -L "$NERD_URL" -o /tmp/JetBrainsMono.zip 2>/dev/null && \
    unzip -o /tmp/JetBrainsMono.zip "*.ttf" -d /usr/local/share/fonts/nerd-fonts/ 2>/dev/null && \
    fc-cache -fv /usr/local/share/fonts/nerd-fonts/ 2>/dev/null && \
    rm -f /tmp/JetBrainsMono.zip && \
    success "JetBrainsMono Nerd Font installiert" || \
    warn "Nerd Fonts Download fehlgeschlagen — manuell installieren"


# ============================================================
# SCHRITT 4 — Audio (PipeWire)
# ============================================================
step "4/10 — Audio (PipeWire)"

wait_apt
apt-get install -y \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    pavucontrol \
    pulseaudio-utils

apt-get remove --purge -y pulseaudio 2>/dev/null || true
sudo -u "$TARGET_USER" systemctl --user enable pipewire pipewire-pulse wireplumber 2>/dev/null || true

success "PipeWire installiert"

# ============================================================
# SCHRITT 5 — Terminal & Apps
# ============================================================
step "5/10 — Terminal & Standard-Apps"

wait_apt
apt-get install -y \
    kitty \
    mc \
    mousepad \
    ristretto \
    file-roller \
    mpv \
    ffmpeg

echo ""
echo -e "${PURPLE}${BOLD}  Dateimanager:${RESET}"
echo -e "  1) PCManFM (grafisch, leicht — empfohlen)"
echo -e "  2) MC      (Terminal, bereits installiert)"
echo -e "  3) Beide"
echo ""
read -rp "$(echo -e ${PURPLE}${BOLD}"Auswahl [1-3]: "${RESET})" FM_CHOICE
case "$FM_CHOICE" in
    1|3) apt-get install -y pcmanfm gvfs gvfs-backends
         success "PCManFM installiert" ;;
    2)   success "MC bereits installiert" ;;
    *)   apt-get install -y pcmanfm gvfs gvfs-backends
         success "PCManFM installiert (Standard)" ;;
esac

if ask_install "VLC Media Player"; then
    apt-get install -y vlc && success "VLC installiert"
fi

if ask_install "GIMP (Bildbearbeitung)"; then
    apt-get install -y gimp && success "GIMP installiert"
fi

if ask_install "VSCodium"; then
    curl -fsSL https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg \
        | gpg --dearmor | tee /usr/share/keyrings/vscodium-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg] https://download.vscodium.com/debs vscodium main" \
        | tee /etc/apt/sources.list.d/vscodium.list
    wait_apt; apt-get update -qq
    apt-get install -y codium && success "VSCodium installiert" || warn "VSCodium fehlgeschlagen"
fi

if ask_install "OnlyOffice"; then
    mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE \
        | gpg --dearmor -o /etc/apt/keyrings/onlyoffice.gpg
    echo "deb [signed-by=/etc/apt/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" \
        | tee /etc/apt/sources.list.d/onlyoffice.list
    wait_apt; apt-get update -qq
    apt-get install -y onlyoffice-desktopeditors && success "OnlyOffice installiert" || warn "OnlyOffice fehlgeschlagen"
fi

# yt-dlp
curl -sL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    -o /usr/local/bin/yt-dlp && chmod +x /usr/local/bin/yt-dlp
success "yt-dlp installiert"

# ============================================================
# SCHRITT 6 — Browser
# ============================================================
step "6/10 — Browser"

echo ""
echo -e "${PURPLE}${BOLD}  Browser Wahl:${RESET}"
echo -e "  1) Zen Browser  (Firefox-Basis, Privacy — empfohlen)"
echo -e "  2) LibreWolf    (gehärteter Firefox, max. Privacy)"
echo -e "  3) Brave        (Chromium-Basis, Privacy)"
echo -e "  4) Firefox-ESR  (Standard, stabil)"
echo -e "  5) Chromium     (leicht)"
echo -e "  6) Keinen"
echo ""
read -rp "$(echo -e ${PURPLE}${BOLD}"Auswahl [1-6]: "${RESET})" BROWSER_CHOICE

DEFAULT_BROWSER_DESKTOP="firefox-esr.desktop"
case "$BROWSER_CHOICE" in
    1)
        info "Installiere Zen Browser..."
        ZEN_URL=""
        ZEN_JSON=$(curl -sf https://api.github.com/repos/zen-browser/desktop/releases/latest 2>/dev/null)
        if [[ -n "$ZEN_JSON" ]]; then
            ZEN_URL=$(echo "$ZEN_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for a in data.get('assets', []):
        if a['name'].endswith('x86_64.AppImage'):
            print(a['browser_download_url'])
            break
except: pass
" 2>/dev/null)
        fi
        if [[ -n "$ZEN_URL" ]]; then
            curl -L "$ZEN_URL" -o /opt/zen-browser.AppImage
            chmod +x /opt/zen-browser.AppImage
            apt-get install -y libfuse2 2>/dev/null || true
            cat > /usr/share/applications/zen-browser.desktop << 'EOF'
[Desktop Entry]
Name=Zen Browser
Comment=Privacy-focused web browser
Exec=/opt/zen-browser.AppImage %u
Icon=firefox
Type=Application
Categories=Network;WebBrowser;
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
StartupNotify=true
EOF
            DEFAULT_BROWSER_DESKTOP="zen-browser.desktop"
            success "Zen Browser installiert"
        else
            warn "Zen Browser nicht verfügbar — Fallback: Firefox-ESR"
            apt-get install -y firefox-esr
            DEFAULT_BROWSER_DESKTOP="firefox-esr.desktop"
        fi ;;
    2)
        curl -fsSL https://deb.librewolf.net/keyring.gpg \
            | gpg --dearmor | tee /usr/share/keyrings/librewolf.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/librewolf.gpg arch=amd64] https://deb.librewolf.net bookworm main" \
            | tee /etc/apt/sources.list.d/librewolf.list
        wait_apt; apt-get update -qq
        apt-get install -y librewolf && success "LibreWolf installiert" || warn "LibreWolf fehlgeschlagen"
        DEFAULT_BROWSER_DESKTOP="librewolf.desktop" ;;
    3)
        curl -fsS https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
            | tee /usr/share/keyrings/brave-browser-archive-keyring.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
            | tee /etc/apt/sources.list.d/brave-browser.list
        wait_apt; apt-get update -qq; apt-get install -y brave-browser
        DEFAULT_BROWSER_DESKTOP="brave-browser.desktop"
        success "Brave installiert" ;;
    4)
        apt-get install -y firefox-esr
        DEFAULT_BROWSER_DESKTOP="firefox-esr.desktop"
        success "Firefox-ESR installiert" ;;
    5)
        apt-get install -y chromium
        DEFAULT_BROWSER_DESKTOP="chromium.desktop"
        success "Chromium installiert" ;;
    *)
        warn "Kein Browser installiert" ;;
esac

# ============================================================
# SCHRITT 7 — Steam & Gaming
# ============================================================
step "7/10 — Steam & Gaming"

if ask_install "Steam"; then
    wait_apt
    apt-get install -y \
        steam steam-devices \
        libvulkan1 libvulkan1:i386 \
        vulkan-tools libgl1-mesa-dri:i386 \
        mesa-vulkan-drivers:i386 \
        gamemode 2>/dev/null || warn "Steam teilweise fehlgeschlagen"
    systemctl enable gamemoded 2>/dev/null || true
    success "Steam + GameMode installiert"

    info "Installiere Proton GE..."
    PROTON_GE_URL=""
    PROTON_GE_JSON=$(curl -sf https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest 2>/dev/null)
    if [[ -n "$PROTON_GE_JSON" ]]; then
        PROTON_GE_URL=$(echo "$PROTON_GE_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for a in data.get('assets', []):
        if a['name'].endswith('.tar.gz'):
            print(a['browser_download_url'])
            break
except: pass
" 2>/dev/null)
    fi
    if [[ -n "$PROTON_GE_URL" ]]; then
        curl -L "$PROTON_GE_URL" -o /tmp/proton-ge.tar.gz
        mkdir -p "$TARGET_HOME/.steam/root/compatibilitytools.d"
        tar -xzf /tmp/proton-ge.tar.gz -C "$TARGET_HOME/.steam/root/compatibilitytools.d/"
        rm -f /tmp/proton-ge.tar.gz
        chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.steam/root/compatibilitytools.d/"
        success "Proton GE installiert"
    else
        warn "Proton GE URL nicht ermittelt — manuell installieren"
    fi
fi

# ============================================================
# SCHRITT 7b — Ollama (Lokale KI)
# ============================================================
step "7b/10 — Ollama (Lokale KI)"

if ask_install "Ollama (lokale KI, kein Modell — nur Engine)"; then
    info "Installiere Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh 2>/dev/null || warn "Ollama Installation fehlgeschlagen"

    # Ollama nicht automatisch starten — nur bei Bedarf via snowfox cli
    systemctl disable ollama 2>/dev/null || true
    systemctl stop ollama 2>/dev/null || true

    success "Ollama installiert (nicht aktiv — starten mit: ollama serve)"
    info "Modelle installieren mit: ollama pull <modell> (z.B. ollama pull mistral)"
fi

# ============================================================
# SCHRITT 8 — Performance & Sicherheit
# ============================================================
step "8/10 — Performance & Sicherheit"

wait_apt
apt-get install -y zram-tools earlyoom ufw
command -v tlp &>/dev/null || apt-get install -y tlp tlp-rdw

cat > /etc/default/zramswap << 'EOF'
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF

# Initramfs auf lz4 umstellen
if [[ -f /etc/initramfs-tools/initramfs.conf ]]; then
    sed -i 's/^COMPRESS=.*/COMPRESS=lz4/' /etc/initramfs-tools/initramfs.conf
    update-initramfs -u 2>/dev/null || true
fi

systemctl enable zramswap earlyoom tlp 2>/dev/null || true

cat > /etc/sysctl.d/99-snowfox.conf << 'EOF'
# RAM & Swap
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_background_ratio=3
vm.dirty_ratio=6

# Netzwerk
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216

# IPv6 Privacy
net.ipv6.conf.all.use_tempaddr=2
net.ipv6.conf.default.use_tempaddr=2

# CPU
kernel.nmi_watchdog=0
EOF

# fstab — noatime + tmpfs ohne Duplikate
info "Optimiere fstab..."
sed -i 's/errors=remount-ro/errors=remount-ro,noatime/g' /etc/fstab

# Duplikate entfernen, einmal sauber setzen
sed -i '/tmpfs \/tmp tmpfs/d' /etc/fstab
echo "tmpfs /tmp tmpfs defaults,noatime,size=4G,mode=1777 0 0" >> /etc/fstab
success "fstab optimiert (noatime, tmpfs einmalig)"

# Firewall
ufw default deny incoming  2>/dev/null || true
ufw default allow outgoing 2>/dev/null || true
ufw --force enable         2>/dev/null || true
success "ufw Firewall aktiviert"

# NetworkManager
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/NetworkManager.conf << 'EOF'
[main]
plugins=ifupdown,keyfile

[ifupdown]
managed=true
EOF

cat > /etc/NetworkManager/conf.d/99-snowfox-privacy.conf << 'EOF'
[device]
wifi.scan-rand-mac-address=yes
[connection]
wifi.cloned-mac-address=stable-privacy
ethernet.cloned-mac-address=stable-privacy
EOF

cat > /etc/NetworkManager/conf.d/99-snowfox-wifi-powersave.conf << 'EOF'
[connection]
wifi.powersave=2
EOF

# DNS-over-TLS
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/snowfox.conf << 'EOF'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net
FallbackDNS=8.8.8.8
DNSSEC=allow-downgrade
DNSOverTLS=opportunistic
EOF
systemctl enable systemd-resolved irqbalance 2>/dev/null || true

# Unnötige Dienste deaktivieren
for svc in avahi-daemon cups-browsed ModemManager colord blueman; do
    systemctl disable "$svc" 2>/dev/null || true
done

# Boot-Verzögerungen eliminieren
systemctl mask NetworkManager-wait-online.service 2>/dev/null || true
systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true

sed -i 's/#HandlePowerKey=.*/HandlePowerKey=ignore/' /etc/systemd/logind.conf

success "Performance & Sicherheit optimiert"

# ============================================================
# SCHRITT 9 — Plymouth & Branding
# ============================================================
step "9/10 — Plymouth & Boot-Screen"

apt-get install -y plymouth plymouth-themes 2>/dev/null || true
PLYMOUTH_DIR="/usr/share/plymouth/themes/snowfox"
mkdir -p "$PLYMOUTH_DIR"

cat > "$PLYMOUTH_DIR/snowfox.plymouth" << 'EOF'
[Plymouth Theme]
Name=SnowFox
Description=SnowFoxOS Boot Theme
ModuleName=script
[script]
ImageDir=/usr/share/plymouth/themes/snowfox
ScriptFile=/usr/share/plymouth/themes/snowfox/snowfox.script
EOF

cat > "$PLYMOUTH_DIR/snowfox.script" << 'EOF'
wallpaper_image = Image("background.png");
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
wallpaper_sprite = Sprite(wallpaper_image);
wallpaper_sprite.SetX(screen_width / 2 - wallpaper_image.GetWidth() / 2);
wallpaper_sprite.SetY(screen_height / 2 - wallpaper_image.GetHeight() / 2);
logo_image = Image("logo.png");
logo_sprite = Sprite(logo_image);
logo_sprite.SetX(screen_width / 2 - logo_image.GetWidth() / 2);
logo_sprite.SetY(screen_height / 2 - logo_image.GetHeight() / 2);
EOF

[[ -f "$SCRIPT_DIR/assets/fuchs.png" ]] && \
    convert "$SCRIPT_DIR/assets/fuchs.png" -resize 200x200 "$PLYMOUTH_DIR/logo.png" 2>/dev/null || true
convert -size 1920x1080 xc:#0f0f0f "$PLYMOUTH_DIR/background.png" 2>/dev/null || true
plymouth-set-default-theme -R snowfox 2>/dev/null || \
    { plymouth-set-default-theme snowfox 2>/dev/null || true; update-initramfs -u 2>/dev/null || true; }

success "Boot-Screen bereit"

# ============================================================
# SCHRITT 10 — Konfiguration & Abschluss
# ============================================================
step "10/10 — Konfiguration & Finishing"

CONFIG_DIR="$TARGET_HOME/.config"
mkdir -p "$CONFIG_DIR/neofetch"
mkdir -p "$TARGET_HOME/Pictures/wallpapers"

# ── Distro-Identität ─────────────────────────────────────────
cat > /etc/os-release << 'EOF'
PRETTY_NAME="SnowFoxOS 2.1"
NAME="SnowFoxOS"
VERSION="2.1"
VERSION_ID="2.1"
ID=snowfoxos
ID_LIKE=debian
HOME_URL="https://github.com/Xr7-Code/SnowFoxOS-v2.1-i3"
ANSI_COLOR="0;35"
EOF

cat > /etc/lsb-release << 'EOF'
DISTRIB_ID=SnowFoxOS
DISTRIB_RELEASE=2.1
DISTRIB_CODENAME=fox
DISTRIB_DESCRIPTION="SnowFoxOS 2.1"
EOF

echo "snowfox"             > /etc/hostname
echo "SnowFoxOS 2.1"       > /etc/issue
echo "SnowFoxOS 2.1 \n \l" > /etc/issue.net
hostname snowfox 2>/dev/null || true
success "Distro-Identität gesetzt"

# ── Theme & GTK ──────────────────────────────────────────────
info "Aktiviere Arc-Dark Design & Papirus Icons..."
mkdir -p "$CONFIG_DIR/xsettingsd"

for version in "3.0" "4.0"; do
    mkdir -p "$CONFIG_DIR/gtk-$version"
    cat > "$CONFIG_DIR/gtk-$version/settings.ini" << GEOF
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Inter 10
gtk-cursor-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
GEOF
done

cat > "$TARGET_HOME/.gtkrc-2.0" << G2EOF
include "/usr/share/themes/Arc-Dark/gtk-2.0/gtkrc"
gtk-theme-name="Arc-Dark"
gtk-icon-theme-name="Papirus-Dark"
gtk-font-name="Inter 10"
G2EOF

cat > "$CONFIG_DIR/xsettingsd/xsettingsd.conf" << XEOF
Net/ThemeName "Arc-Dark"
Net/IconThemeName "Papirus-Dark"
Gtk/CursorThemeName "Adwaita"
XEOF

# ── Qt Styling ───────────────────────────────────────────────
info "Konfiguriere Qt-Styling..."
mkdir -p "$CONFIG_DIR/qt5ct" "$CONFIG_DIR/qt6ct"

cat > "$CONFIG_DIR/qt5ct/qt5ct.conf" << Q5EOF
[Appearance]
style=gtk2
Q5EOF

cat > "$CONFIG_DIR/qt6ct/qt6ct.conf" << Q6EOF
[Appearance]
style=gtk2
Q6EOF

# ── Neofetch ─────────────────────────────────────────────────
cat > "$CONFIG_DIR/neofetch/config.conf" << EOF
print_info() {
    info title
    info underline
    info "OS"         distro
    info "Kernel"     kernel
    info "Uptime"     uptime
    info "Packages"   packages
    info "Shell"      shell
    info "Resolution" resolution
    info "WM"         wm
    info "CPU"        cpu
    info "GPU"        gpu
    info "Memory"     memory
}
image_backend="ascii"
ascii_distro=""
image_source="${TARGET_HOME}/.config/neofetch/snowfox.txt"
ascii_colors=(5 7)
EOF

cat > "$CONFIG_DIR/neofetch/snowfox.txt" << 'ASCIIEOF'
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;8;8;8m [0m[38;2;37;37;37m.[0m[38;2;58;58;58m.[0m[38;2;76;76;75m,[0m[38;2;88;89;87m;[0m[38;2;99;99;99m:[0m[38;2;101;101;101m:[0m[38;2;101;102;102m:[0m[38;2;101;101;101m:[0m[38;2;96;96;96m;[0m[38;2;85;85;85m,[0m[38;2;71;71;71m'[0m[38;2;54;54;54m.[0m[38;2;31;31;31m.[0m[38;2;3;3;3m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;39;39;39m.[0m[38;2;95;95;95m;[0m[38;2;141;142;141mo[0m[38;2;180;180;180mO[0m[38;2;217;217;217mX[0m[38;2;249;249;249mW[0m[38;2;107;107;107m:[0m[38;2;176;176;176m [0m[38;2;62;62;61m.[0m[38;2;133;134;132ml[0m[38;2;139;140;139mo[0m[38;2;104;104;104m:[0m[38;2;147;147;147m [0m[38;2;241;241;240mW[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;253;253;252mM[0m[38;2;253;253;252mM[0m[38;2;253;253;253mM[0m[38;2;244;244;244mW[0m[38;2;213;213;213mK[0m[38;2;179;179;179mk[0m[38;2;140;140;140mo[0m[38;2;93;92;92m;[0m[38;2;40;40;40m.[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;6;6;6m [0m[38;2;112;112;113mc[0m[38;2;118;118;118mc[0m[38;2;93;93;93m;[0m[38;2;53;53;53m.[0m[38;2;3;3;3m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;49;49;49m [0m[38;2;118;118;118m [0m[38;2;180;180;180m [0m[38;2;211;211;211m [0m[38;2;215;215;215m [0m[38;2;226;226;226m [0m[38;2;29;29;29m [0m[38;2;9;9;9m [0m[38;2;42;42;42m.[0m[38;2;105;105;105m:[0m[38;2;177;178;177mk[0m[38;2;241;241;241mW[0m[38;2;212;212;212mK[0m[38;2;168;168;168mx[0m[38;2;228;228;228mN[0m[38;2;52;52;52m.[0m[38;2;38;38;38m.[0m[38;2;254;253;253mM[0m[38;2;253;253;253mM[0m[38;2;254;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;252;252mM[0m[38;2;253;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;221;221;221mX[0m[38;2;156;156;156md[0m[38;2;84;84;84m,[0m[38;2;6;6;6m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;93;93;93m;[0m[38;2;220;220;220mX[0m[38;2;155;155;155md[0m[38;2;178;178;178mk[0m[38;2;250;250;250mM[0m[38;2;239;240;239mW[0m[38;2;175;175;174mk[0m[38;2;98;97;97m;[0m[38;2;11;11;11m [0m[38;2;12;12;12m [0m[38;2;85;85;84m,[0m[38;2;110;110;110mc[0m[38;2;131;131;130ml[0m[38;2;145;146;145md[0m[38;2;155;155;155md[0m[38;2;159;159;159mx[0m[38;2;151;151;151md[0m[38;2;145;145;145mo[0m[38;2;34;34;34m.[0m[38;2;120;120;120mc[0m[38;2;231;231;230mN[0m[38;2;253;253;252mM[0m[38;2;248;248;248mW[0m[38;2;114;115;114mc[0m[38;2;48;48;49m.[0m[38;2;190;190;191mO[0m[38;2;219;219;219mX[0m[38;2;206;206;205mK[0m[38;2;23;23;23m [0m[38;2;238;238;238mW[0m[38;2;254;254;253mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;253mM[0m[38;2;254;254;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;237;237;237mN[0m[38;2;159;159;159mx[0m[38;2;63;63;63m.[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;101;101;101m;[0m[38;2;222;222;221mX[0m[38;2;206;206;206mK[0m[38;2;81;82;81m,[0m[38;2;49;50;50m.[0m[38;2;200;201;200m0[0m[38;2;253;254;253mM[0m[38;2;253;253;253mM[0m[38;2;243;243;243mW[0m[38;2;193;193;193m0[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;252mM[0m[38;2;242;243;242mW[0m[38;2;253;253;252mM[0m[38;2;252;253;252mM[0m[38;2;252;253;252mM[0m[38;2;99;99;99m:[0m[38;2;5;5;6m [0m[38;2;107;107;107m:[0m[38;2;218;218;219mX[0m[38;2;225;226;226mN[0m[38;2;246;247;246mM[0m[38;2;0;0;0m [0m[38;2;203;204;203mK[0m[38;2;254;254;253mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;253mM[0m[38;2;254;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;252mM[0m[38;2;252;253;252mM[0m[38;2;252;253;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;187;187;186mO[0m[38;2;43;43;43m.[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;26;26;26m [0m[38;2;241;241;241mW[0m[38;2;205;205;206mK[0m[38;2;168;168;168mx[0m[38;2;65;65;65m'[0m[38;2;54;54;55m.[0m[38;2;223;223;223mX[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;252;253mM[0m[38;2;206;206;206mK[0m[38;2;207;207;207mK[0m[38;2;213;213;213mK[0m[38;2;222;223;223mX[0m[38;2;234;234;235mN[0m[38;2;132;132;132ml[0m[38;2;3;3;3m [0m[38;2;224;224;224mX[0m[38;2;248;248;248mW[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;253mM[0m[38;2;254;254;253mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;252;253;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;251mM[0m[38;2;249;249;249mM[0m[38;2;153;153;152md[0m[38;2;9;9;8m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;13;13;13m [0m[38;2;121;120;120ml[0m[38;2;221;221;221mX[0m[38;2;204;204;205mK[0m[38;2;224;224;225mX[0m[38;2;248;249;248mW[0m[38;2;253;253;253mM[0m[38;2;253;254;253mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;254;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;247;247;247mW[0m[38;2;129;129;129ml[0m[38;2;76;76;76m [0m[38;2;75;75;76m,[0m[38;2;210;210;211mK[0m[38;2;220;221;221mX[0m[38;2;227;227;228mN[0m[38;2;232;233;233mN[0m[38;2;233;233;233mN[0m[38;2;229;229;230mN[0m[38;2;224;224;225mX[0m[38;2;87;87;87m,[0m[38;2;180;180;180m [0m[38;2;159;159;159m [0m[38;2;145;145;145m [0m[38;2;128;129;129ml[0m[38;2;175;175;175mk[0m[38;2;201;200;201m0[0m[38;2;226;225;226mN[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;251mM[0m[38;2;251;252;251mM[0m[38;2;252;252;251mM[0m[38;2;222;222;222mX[0m[38;2;44;44;44m.[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;43;43;43m [0m[38;2;5;5;5m [0m[38;2;243;243;243mW[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;254;253mM[0m[38;2;254;254;253mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;234;234;234mN[0m[38;2;108;108;108m:[0m[38;2;25;26;26m [0m[38;2;157;157;157m [0m[38;2;192;193;195mO[0m[38;2;209;210;211mK[0m[38;2;212;212;214mK[0m[38;2;13;13;13m [0m[38;2;12;12;12m [0m[38;2;106;106;106m:[0m[38;2;128;128;128ml[0m[38;2;165;165;164mx[0m[38;2;200;200;199m0[0m[38;2;233;232;232mN[0m[38;2;251;251;251mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;252;252;251mM[0m[38;2;252;253;252mM[0m[38;2;252;253;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;251mM[0m[38;2;252;251;251mM[0m[38;2;242;242;241mW[0m[38;2;60;60;59m.[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;1;1;1m [0m[38;2;129;129;128ml[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;250;251;250mM[0m[38;2;241;241;241mW[0m[38;2;237;237;237mN[0m[38;2;234;234;235mN[0m[38;2;234;234;235mN[0m[38;2;237;237;237mN[0m[38;2;241;241;241mW[0m[38;2;244;244;244mW[0m[38;2;247;248;247mW[0m[38;2;102;102;102m:[0m[38;2;81;81;81m [0m[38;2;11;11;11m [0m[38;2;96;95;95m;[0m[38;2;2;2;2m [0m[38;2;91;91;91m;[0m[38;2;195;196;195m0[0m[38;2;232;232;231mN[0m[38;2;237;237;236mN[0m[38;2;241;241;241mW[0m[38;2;244;244;243mW[0m[38;2;248;248;247mW[0m[38;2;252;252;252mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;251;252;251mM[0m[38;2;243;244;243mW[0m[38;2;22;22;22m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;24;24;24m [0m[38;2;183;183;183mO[0m[38;2;253;253;253mM[0m[38;2;247;247;247mW[0m[38;2;239;239;240mW[0m[38;2;234;234;234mN[0m[38;2;228;229;229mN[0m[38;2;224;225;225mX[0m[38;2;216;216;216mX[0m[38;2;225;225;225mX[0m[38;2;234;235;235mN[0m[38;2;246;247;247mW[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;253mM[0m[38;2;254;254;254mM[0m[38;2;254;254;253mM[0m[38;2;253;254;253mM[0m[38;2;237;237;237mN[0m[38;2;186;187;188mO[0m[38;2;131;131;133ml[0m[38;2;149;149;151md[0m[38;2;195;196;196m0[0m[38;2;231;232;232mN[0m[38;2;236;237;237mN[0m[38;2;240;240;241mW[0m[38;2;241;241;242mW[0m[38;2;234;234;234mN[0m[38;2;195;195;195m0[0m[38;2;15;15;15m [0m[38;2;14;14;13m [0m[38;2;44;44;44m [0m[38;2;96;97;97m;[0m[38;2;222;223;223mX[0m[38;2;219;220;220mX[0m[38;2;225;225;226mX[0m[38;2;226;226;226mX[0m[38;2;242;242;242mW[0m[38;2;252;252;252mM[0m[38;2;253;254;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;252;253;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;251;252;252mM[0m[38;2;251;252;251mM[0m[38;2;161;161;161mx[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;3;3;3m [0m[38;2;152;152;151md[0m[38;2;237;236;236mN[0m[38;2;239;238;239mW[0m[38;2;241;241;241mW[0m[38;2;241;241;241mW[0m[38;2;238;238;238mW[0m[38;2;196;197;197m0[0m[38;2;158;158;158mx[0m[38;2;135;135;135mo[0m[38;2;118;118;119mc[0m[38;2;166;166;167mx[0m[38;2;236;236;236mN[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;239;239;239mW[0m[38;2;179;179;179mk[0m[38;2;132;132;133ml[0m[38;2;219;219;220mX[0m[38;2;248;248;248mW[0m[38;2;253;254;253mM[0m[38;2;246;247;247mW[0m[38;2;153;153;153md[0m[38;2;187;187;187m [0m[38;2;137;137;137m [0m[38;2;107;107;107m [0m[38;2;78;79;79m,[0m[38;2;42;42;43m.[0m[38;2;77;77;76m,[0m[38;2;62;62;62m.[0m[38;2;92;92;92m;[0m[38;2;101;101;101m:[0m[38;2;101;101;101m:[0m[38;2;105;105;106m:[0m[38;2;124;124;124ml[0m[38;2;106;106;106m:[0m[38;2;160;160;160m [0m[38;2;213;213;213m [0m[38;2;242;242;242mW[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;252;253;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;249;249;249mW[0m[38;2;219;219;219mX[0m[38;2;11;11;11m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;2;2;2m [0m[38;2;80;80;80m [0m[38;2;181;181;181m [0m[38;2;201;201;201m0[0m[38;2;241;241;240mW[0m[38;2;247;247;246mW[0m[38;2;252;252;251mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;253;253mM[0m[38;2;246;246;246mW[0m[38;2;225;225;225mX[0m[38;2;222;223;223mX[0m[38;2;246;246;246mW[0m[38;2;255;255;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;225;225;226mX[0m[38;2;231;232;232mN[0m[38;2;252;252;252mM[0m[38;2;250;250;250mM[0m[38;2;99;99;99m;[0m[38;2;138;138;138m [0m[38;2;52;52;53m.[0m[38;2;98;98;98m;[0m[38;2;140;140;139mo[0m[38;2;190;190;190mO[0m[38;2;226;227;226mN[0m[38;2;252;252;251mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;250;251;250mM[0m[38;2;232;232;232mN[0m[38;2;208;208;208mK[0m[38;2;226;225;226mX[0m[38;2;253;253;253mM[0m[38;2;253;253;252mM[0m[38;2;252;253;252mM[0m[38;2;252;253;252mM[0m[38;2;252;253;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;251;251;252mM[0m[38;2;252;252;252mM[0m[38;2;235;235;235mN[0m[38;2;221;222;222mX[0m[38;2;35;35;35m.[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;25;25;25m [0m[38;2;29;28;28m.[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;29;29;29m [0m[38;2;81;81;81m [0m[38;2;124;124;124m [0m[38;2;155;155;155m [0m[38;2;179;179;179m [0m[38;2;198;198;198m [0m[38;2;12;12;12m [0m[38;2;237;238;237mW[0m[38;2;250;250;250mM[0m[38;2;249;249;249mM[0m[38;2;240;240;240mW[0m[38;2;245;245;245mW[0m[38;2;216;216;216mX[0m[38;2;219;220;220mX[0m[38;2;239;240;239mW[0m[38;2;251;252;251mM[0m[38;2;123;124;124ml[0m[38;2;5;5;5m [0m[38;2;84;84;85m,[0m[38;2;169;169;169mk[0m[38;2;235;235;234mN[0m[38;2;238;238;237mW[0m[38;2;238;239;238mW[0m[38;2;241;242;242mW[0m[38;2;244;245;244mW[0m[38;2;247;248;248mW[0m[38;2;251;252;252mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;254;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;252;253;252mM[0m[38;2;252;253;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;250;250;250mM[0m[38;2;241;241;241mW[0m[38;2;252;252;252mM[0m[38;2;243;244;243mW[0m[38;2;220;221;222mX[0m[38;2;214;215;215mX[0m[38;2;24;24;25m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;28;28;28m [0m[38;2;232;231;230mN[0m[38;2;205;204;202mK[0m[38;2;156;156;155md[0m[38;2;119;119;119mc[0m[38;2;95;95;95m;[0m[38;2;84;84;84m,[0m[38;2;81;81;81m,[0m[38;2;90;90;90m;[0m[38;2;105;105;105m:[0m[38;2;108;108;108m:[0m[38;2;100;100;100m:[0m[38;2;72;72;72m'[0m[38;2;151;151;151m [0m[38;2;141;140;141mo[0m[38;2;98;98;99m;[0m[38;2;19;19;20m [0m[38;2;42;43;43m.[0m[38;2;150;151;151md[0m[38;2;158;158;158m [0m[38;2;36;36;36m.[0m[38;2;163;163;163mx[0m[38;2;226;226;227mN[0m[38;2;232;232;233mN[0m[38;2;237;237;237mN[0m[38;2;242;242;242mW[0m[38;2;250;250;250mM[0m[38;2;254;254;254mM[0m[38;2;253;254;254mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;252;253;252mM[0m[38;2;252;253;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;245;245;245mW[0m[38;2;227;228;227mN[0m[38;2;246;246;246mW[0m[38;2;243;243;243mW[0m[38;2;222;222;223mX[0m[38;2;220;220;221mX[0m[38;2;199;200;200m0[0m[38;2;39;39;39m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;28;28;28m [0m[38;2;196;196;196m0[0m[38;2;225;225;226mX[0m[38;2;244;244;244mW[0m[38;2;254;253;253mM[0m[38;2;254;253;253mM[0m[38;2;254;254;253mM[0m[38;2;254;254;253mM[0m[38;2;253;253;253mM[0m[38;2;249;249;249mW[0m[38;2;243;242;242mW[0m[38;2;236;235;236mN[0m[38;2;225;225;225mX[0m[38;2;153;153;153md[0m[38;2;103;103;103m:[0m[38;2;111;112;112mc[0m[38;2;107;107;108m:[0m[38;2;101;101;101m:[0m[38;2;103;103;104m:[0m[38;2;136;136;137mo[0m[38;2;210;209;210mK[0m[38;2;226;226;226mX[0m[38;2;235;235;236mN[0m[38;2;237;238;238mW[0m[38;2;244;245;245mW[0m[38;2;251;251;251mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;252;253;253mM[0m[38;2;252;253;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;247;247;247mW[0m[38;2;232;232;232mN[0m[38;2;231;231;231mN[0m[38;2;248;248;248mW[0m[38;2;237;237;237mN[0m[38;2;221;221;222mX[0m[38;2;220;220;221mX[0m[38;2;204;205;206mK[0m[38;2;76;76;76m,[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;15;15;15m [0m[38;2;242;241;240mW[0m[38;2;225;225;224mX[0m[38;2;227;227;227mN[0m[38;2;244;244;244mW[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;253mM[0m[38;2;254;254;253mM[0m[38;2;254;254;253mM[0m[38;2;251;251;251mM[0m[38;2;245;246;245mW[0m[38;2;241;242;241mW[0m[38;2;240;240;240mW[0m[38;2;240;240;240mW[0m[38;2;241;241;242mW[0m[38;2;244;245;245mW[0m[38;2;249;250;249mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;252;253;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;250;251;251mM[0m[38;2;241;241;241mW[0m[38;2;232;232;232mN[0m[38;2;233;233;233mN[0m[38;2;245;245;245mW[0m[38;2;244;244;244mW[0m[38;2;227;227;228mN[0m[38;2;221;221;222mX[0m[38;2;218;219;220mX[0m[38;2;203;204;205mK[0m[38;2;146;147;147md[0m[38;2;42;42;42m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;3;3;3m [0m[38;2;18;18;18m [0m[38;2;253;254;253mM[0m[38;2;244;245;244mW[0m[38;2;232;232;232mN[0m[38;2;226;226;226mN[0m[38;2;238;237;237mN[0m[38;2;248;248;248mW[0m[38;2;254;254;254mM[0m[38;2;254;254;254mM[0m[38;2;254;254;253mM[0m[38;2;254;254;253mM[0m[38;2;254;254;253mM[0m[38;2;254;254;253mM[0m[38;2;253;254;253mM[0m[38;2;254;254;253mM[0m[38;2;253;253;253mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;254;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;252;253;253mM[0m[38;2;252;253;253mM[0m[38;2;252;253;253mM[0m[38;2;252;253;253mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;249;249;249mW[0m[38;2;243;243;243mW[0m[38;2;240;241;240mW[0m[38;2;246;247;246mW[0m[38;2;252;252;252mM[0m[38;2;242;243;243mW[0m[38;2;229;230;230mN[0m[38;2;221;222;223mX[0m[38;2;221;222;223mX[0m[38;2;213;214;215mK[0m[38;2;199;201;202m0[0m[38;2;137;138;139mo[0m[38;2;67;67;67m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;2;2;2m [0m[38;2;115;115;115m [0m[38;2;181;181;181mO[0m[38;2;250;250;250mM[0m[38;2;252;251;251mM[0m[38;2;243;243;242mW[0m[38;2;235;235;234mN[0m[38;2;233;233;233mN[0m[38;2;235;235;235mN[0m[38;2;240;240;240mW[0m[38;2;247;246;246mW[0m[38;2;252;252;252mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;253;253;253mM[0m[38;2;252;253;253mM[0m[38;2;252;253;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;251;252;251mM[0m[38;2;252;252;251mM[0m[38;2;251;251;251mM[0m[38;2;251;251;251mM[0m[38;2;251;251;251mM[0m[38;2;251;251;251mM[0m[38;2;252;252;252mM[0m[38;2;251;251;251mM[0m[38;2;244;244;244mW[0m[38;2;234;234;235mN[0m[38;2;224;225;225mX[0m[38;2;221;222;222mX[0m[38;2;221;222;223mX[0m[38;2;216;217;218mX[0m[38;2;204;205;206mK[0m[38;2;198;199;200m0[0m[38;2;57;57;58m.[0m[38;2;45;45;45m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;46;46;46m [0m[38;2;17;17;17m [0m[38;2;232;232;232mN[0m[38;2;243;243;243mW[0m[38;2;250;250;250mM[0m[38;2;253;253;253mM[0m[38;2;252;252;252mM[0m[38;2;248;247;247mW[0m[38;2;243;242;242mW[0m[38;2;241;241;240mW[0m[38;2;243;242;242mW[0m[38;2;244;245;244mW[0m[38;2;247;247;247mW[0m[38;2;250;250;250mM[0m[38;2;253;252;252mM[0m[38;2;253;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;251mM[0m[38;2;251;251;251mM[0m[38;2;252;251;251mM[0m[38;2;252;251;251mM[0m[38;2;249;249;249mW[0m[38;2;244;244;244mW[0m[38;2;238;238;238mW[0m[38;2;231;231;231mN[0m[38;2;223;223;224mX[0m[38;2;221;221;222mX[0m[38;2;221;221;222mX[0m[38;2;221;221;222mX[0m[38;2;215;215;216mX[0m[38;2;205;206;207mK[0m[38;2;199;199;200m0[0m[38;2;118;118;119mc[0m[38;2;105;105;105m [0m[38;2;11;11;11m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;1;1;1m [0m[38;2;78;78;78m [0m[38;2;20;20;20m [0m[38;2;219;219;220mX[0m[38;2;226;226;227mN[0m[38;2;235;235;235mN[0m[38;2;241;241;241mW[0m[38;2;246;247;246mW[0m[38;2;251;251;250mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;251mM[0m[38;2;252;252;251mM[0m[38;2;252;252;251mM[0m[38;2;252;252;251mM[0m[38;2;252;252;251mM[0m[38;2;252;252;251mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;252;252;252mM[0m[38;2;251;251;251mM[0m[38;2;250;250;250mM[0m[38;2;249;250;249mM[0m[38;2;247;248;247mW[0m[38;2;245;245;245mW[0m[38;2;243;243;243mW[0m[38;2;241;241;241mW[0m[38;2;238;238;238mW[0m[38;2;234;234;234mN[0m[38;2;230;230;230mN[0m[38;2;226;226;225mX[0m[38;2;221;222;222mX[0m[38;2;221;222;222mX[0m[38;2;221;221;221mX[0m[38;2;221;221;221mX[0m[38;2;221;221;222mX[0m[38;2;216;217;217mX[0m[38;2;209;210;210mK[0m[38;2;202;203;203m0[0m[38;2;199;200;201m0[0m[38;2;132;132;133ml[0m[38;2;119;119;119m [0m[38;2;24;24;24m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;1;1;1m [0m[38;2;58;58;58m [0m[38;2;133;133;133m [0m[38;2;45;45;45m.[0m[38;2;219;220;220mX[0m[38;2;219;220;220mX[0m[38;2;221;222;222mX[0m[38;2;226;226;226mN[0m[38;2;230;230;230mN[0m[38;2;233;233;233mN[0m[38;2;236;236;236mN[0m[38;2;239;239;238mW[0m[38;2;241;241;241mW[0m[38;2;243;243;243mW[0m[38;2;244;244;244mW[0m[38;2;245;245;245mW[0m[38;2;245;246;245mW[0m[38;2;246;246;246mW[0m[38;2;242;243;243mW[0m[38;2;239;240;239mW[0m[38;2;235;235;235mN[0m[38;2;232;233;232mN[0m[38;2;230;230;230mN[0m[38;2;227;227;227mN[0m[38;2;224;224;224mX[0m[38;2;221;222;222mX[0m[38;2;221;221;221mX[0m[38;2;221;222;221mX[0m[38;2;221;221;221mX[0m[38;2;221;222;221mX[0m[38;2;221;221;221mX[0m[38;2;218;218;218mX[0m[38;2;213;213;214mK[0m[38;2;208;208;209mK[0m[38;2;202;203;203m0[0m[38;2;200;201;201m0[0m[38;2;178;179;180mk[0m[38;2;158;158;158m [0m[38;2;93;93;93m [0m[38;2;23;23;23m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;4;4;4m [0m[38;2;50;50;50m [0m[38;2;106;106;106m [0m[38;2;159;159;159m [0m[38;2;56;55;55m.[0m[38;2;219;219;219mX[0m[38;2;219;219;219mX[0m[38;2;220;220;220mX[0m[38;2;220;220;220mX[0m[38;2;220;220;220mX[0m[38;2;220;220;220mX[0m[38;2;220;220;220mX[0m[38;2;220;220;220mX[0m[38;2;220;220;220mX[0m[38;2;220;221;221mX[0m[38;2;220;220;221mX[0m[38;2;220;220;220mX[0m[38;2;220;220;221mX[0m[38;2;220;220;221mX[0m[38;2;220;220;221mX[0m[38;2;220;220;221mX[0m[38;2;219;220;220mX[0m[38;2;217;218;218mX[0m[38;2;214;215;215mX[0m[38;2;212;212;212mK[0m[38;2;208;208;209mK[0m[38;2;205;205;206mK[0m[38;2;201;201;202m0[0m[38;2;199;199;200m0[0m[38;2;196;196;197m0[0m[38;2;14;14;14m [0m[38;2;130;130;130m [0m[38;2;85;85;85m [0m[38;2;31;31;31m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;4;4;4m [0m[38;2;36;36;36m [0m[38;2;71;71;71m [0m[38;2;104;104;104m [0m[38;2;133;133;133m [0m[38;2;154;154;154m [0m[38;2;175;175;175m [0m[38;2;7;7;7m [0m[38;2;178;178;178mk[0m[38;2;207;208;208mK[0m[38;2;206;206;207mK[0m[38;2;205;205;206mK[0m[38;2;205;205;206mK[0m[38;2;205;204;205mK[0m[38;2;204;203;204mK[0m[38;2;202;202;203m0[0m[38;2;199;200;201m0[0m[38;2;197;198;199m0[0m[38;2;181;181;182mO[0m[38;2;21;21;21m [0m[38;2;169;169;169m [0m[38;2;147;147;147m [0m[38;2;122;122;122m [0m[38;2;94;94;94m [0m[38;2;64;64;64m [0m[38;2;30;30;30m [0m[38;2;2;2;2m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;13;13;13m [0m[38;2;24;24;24m [0m[38;2;32;32;32m [0m[38;2;38;38;38m [0m[38;2;43;43;43m [0m[38;2;47;47;47m [0m[38;2;44;44;44m [0m[38;2;40;40;40m [0m[38;2;36;36;36m [0m[38;2;26;26;26m [0m[38;2;15;15;15m [0m[38;2;2;2;2m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m
[0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m[38;2;0;0;0m [0m

ASCIIEOF

# ── Repo-Configs kopieren ────────────────────────────────────
if [[ -d "$SCRIPT_DIR/configs" ]]; then
    cp -r "$SCRIPT_DIR/configs/"* "$CONFIG_DIR/"
    success "Konfigurationsdateien kopiert"

    # Rofi
    sed -i 's/show-icons: .*/show-icons: false;/' "$CONFIG_DIR/rofi/config.rasi" 2>/dev/null
    sed -i 's/icon-theme: .*/icon-theme: "Papirus-Dark";/' "$CONFIG_DIR/rofi/config.rasi" 2>/dev/null

    # Picom — optimiert, kein Fading
    if [[ -f "$CONFIG_DIR/picom.conf" ]]; then
        sed -i 's/backend = .*/backend = "glx";/' "$CONFIG_DIR/picom.conf"
        sed -i 's/shadow = .*/shadow = true;/' "$CONFIG_DIR/picom.conf"
        sed -i 's/fading = .*/fading = false;/' "$CONFIG_DIR/picom.conf"
        sed -i 's/dock = { shadow = false; }/dock = { shadow = false; }/g' "$CONFIG_DIR/picom.conf"
    fi

    # i3: Dateimanager-Shortcut auf PCManFM, Netzwerk-Shortcut auf nmtui
    I3_CONFIG_PATH="$CONFIG_DIR/i3/config"
    if [[ -f "$I3_CONFIG_PATH" ]]; then
        if grep -q '^bindsym \$mod+e' "$I3_CONFIG_PATH"; then
            sed -i 's|^bindsym \$mod+e.*|bindsym $mod+e exec pcmanfm|' "$I3_CONFIG_PATH"
        else
            echo 'bindsym $mod+e exec pcmanfm' >> "$I3_CONFIG_PATH"
        fi

        if grep -q '^bindsym \$mod+n' "$I3_CONFIG_PATH"; then
            sed -i 's|^bindsym \$mod+n.*|bindsym $mod+n exec kitty -e nmtui|' "$I3_CONFIG_PATH"
        else
            echo 'bindsym $mod+n exec kitty -e nmtui' >> "$I3_CONFIG_PATH"
        fi
        success "i3-Shortcuts gesetzt: \$mod+e (PCManFM), \$mod+n (nmtui)"
    fi
else
    warn "configs/-Verzeichnis nicht gefunden"
fi

# Skripte ausführbar machen
find "$CONFIG_DIR" -name "*.sh" -exec chmod +x {} +

# ── Wallpaper ────────────────────────────────────────────────
[[ -d "$SCRIPT_DIR/wallpapers" ]] && \
    cp -r "$SCRIPT_DIR/wallpapers/." "$TARGET_HOME/Pictures/wallpapers/"

DEFAULT_WP=$(ls "$TARGET_HOME/Pictures/wallpapers" 2>/dev/null | grep -iE "\.jpg$|\.png$|\.webp$|\.jpeg$" | head -n 1)
if [[ -n "$DEFAULT_WP" ]]; then
    echo "#!/bin/sh" > "$TARGET_HOME/.fehbg"
    echo "feh --bg-fill '$TARGET_HOME/Pictures/wallpapers/$DEFAULT_WP'" >> "$TARGET_HOME/.fehbg"
    chmod +x "$TARGET_HOME/.fehbg"
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.fehbg"
    info "Standard-Wallpaper gesetzt: $DEFAULT_WP"
fi

# ── Polybar — Laptop/Desktop automatisch ─────────────────────
POLYBAR_CONF="$CONFIG_DIR/polybar/config.ini"
if [[ -f "$POLYBAR_CONF" ]]; then
    if [[ "$IS_LAPTOP" == "true" ]]; then
        BAT_NAME=$(ls /sys/class/power_supply/ 2>/dev/null | grep -E "BAT|battery" | head -1)
        [[ -n "$BAT_NAME" ]] && sed -i "s/battery = BAT1/battery = $BAT_NAME/" "$POLYBAR_CONF"

        BL_NAME=$(ls /sys/class/backlight/ 2>/dev/null | head -1)
        [[ -n "$BL_NAME" ]] && sed -i "s/card = intel_backlight/card = $BL_NAME/" "$POLYBAR_CONF"

        sed -i 's/^modules-right =.*/modules-right = backlight battery memory network pulseaudio/' "$POLYBAR_CONF"
        success "Polybar: Laptop-Modus (Akku + Helligkeit aktiv)"
    else
        sed -i 's/^modules-right =.*/modules-right = memory network pulseaudio/' "$POLYBAR_CONF"
        success "Polybar: Desktop-Modus (kein Akku/Helligkeit)"
    fi
fi

# ── modprobe Configs ─────────────────────────────────────────
if [[ -d "$SCRIPT_DIR/configs/modprobe" ]]; then
    cp "$SCRIPT_DIR/configs/modprobe/amdgpu.conf" /etc/modprobe.d/ 2>/dev/null || true
    cp "$SCRIPT_DIR/configs/modprobe/nvidia.conf"  /etc/modprobe.d/ 2>/dev/null || true
    update-initramfs -u 2>/dev/null || true
    success "modprobe Configs installiert"
fi

# ── Skripte installieren ─────────────────────────────────────
[[ -f "$SCRIPT_DIR/configs/powermenu.sh" ]] && \
    cp "$SCRIPT_DIR/configs/powermenu.sh" /usr/local/bin/snowfox-powermenu && \
    chmod +x /usr/local/bin/snowfox-powermenu

# display.sh — mit i3 reload und Polybar-Neustart
if [[ -f "$SCRIPT_DIR/configs/snowfox-display.sh" ]]; then
    cp "$SCRIPT_DIR/configs/snowfox-display.sh" "$CONFIG_DIR/snowfox-display.sh"
    if ! grep -q "polybar/launch.sh" "$CONFIG_DIR/snowfox-display.sh"; then
        sed -i 's/i3-msg restart/i3-msg reload/' "$CONFIG_DIR/snowfox-display.sh"
        echo "" >> "$CONFIG_DIR/snowfox-display.sh"
        echo "sleep 0.5" >> "$CONFIG_DIR/snowfox-display.sh"
        echo "~/.config/polybar/launch.sh" >> "$CONFIG_DIR/snowfox-display.sh"
    fi
    chmod +x "$CONFIG_DIR/snowfox-display.sh"
    success "snowfox-display.sh installiert"
fi

# launch.sh — mit sleep 2 und primary-Fallback
mkdir -p "$CONFIG_DIR/polybar"
cat > "$CONFIG_DIR/polybar/launch.sh" << 'LAUNCHEOF'
#!/bin/bash
# SnowFoxOS — Polybar Starter
sleep 2
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.1; done
PRIMARY=$(xrandr --query | grep " connected primary" | cut -d" " -f1)
if [[ -z "$PRIMARY" ]]; then
    PRIMARY=$(xrandr --query | grep " connected" | head -1 | cut -d" " -f1)
fi
MONITOR=$PRIMARY polybar snowfox 2>/tmp/polybar.log &
LAUNCHEOF
chmod +x "$CONFIG_DIR/polybar/launch.sh"
success "polybar/launch.sh installiert"

[[ -f "$SCRIPT_DIR/snowfox" ]] && \
    cp "$SCRIPT_DIR/snowfox" /usr/local/bin/snowfox && chmod +x /usr/local/bin/snowfox

[[ -f "$SCRIPT_DIR/snowfox-greeting.sh" ]] && \
    cp "$SCRIPT_DIR/snowfox-greeting.sh" /usr/local/bin/snowfox-greeting && \
    chmod +x /usr/local/bin/snowfox-greeting

grep -q "snowfox-greeting" "$TARGET_HOME/.bashrc" 2>/dev/null || \
    printf '\n# SnowFoxOS Greeting\n[[ -x /usr/local/bin/snowfox-greeting ]] && snowfox-greeting\n' \
    >> "$TARGET_HOME/.bashrc"

# ── Standard-Apps ────────────────────────────────────────────
echo ""
echo -e "${PURPLE}${BOLD}  Standard-Texteditor:${RESET}"
echo -e "  1) Mousepad (Standard)"
echo -e "  2) VSCodium"
read -rp "$(echo -e ${PURPLE}${BOLD}"Auswahl [1-2]: "${RESET})" DEFAULT_EDITOR
case "$DEFAULT_EDITOR" in
    2) DEFAULT_EDITOR_DESKTOP="codium.desktop" ;;
    *) DEFAULT_EDITOR_DESKTOP="mousepad.desktop" ;;
esac

DEFAULT_FM_DESKTOP="pcmanfm.desktop"

cat > "$CONFIG_DIR/mimeapps.list" << MEOF
[Default Applications]
inode/directory=$DEFAULT_FM_DESKTOP
text/plain=$DEFAULT_EDITOR_DESKTOP
text/x-python=$DEFAULT_EDITOR_DESKTOP
text/x-shellscript=$DEFAULT_EDITOR_DESKTOP
application/x-shellscript=$DEFAULT_EDITOR_DESKTOP
x-scheme-handler/http=$DEFAULT_BROWSER_DESKTOP
x-scheme-handler/https=$DEFAULT_BROWSER_DESKTOP
text/html=$DEFAULT_BROWSER_DESKTOP
application/xhtml+xml=$DEFAULT_BROWSER_DESKTOP
application/pdf=$DEFAULT_BROWSER_DESKTOP
image/png=ristretto.desktop
image/jpeg=ristretto.desktop
image/gif=ristretto.desktop
video/mp4=mpv.desktop
video/x-matroska=mpv.desktop
audio/mpeg=mpv.desktop
application/zip=file-roller.desktop
application/x-tar=file-roller.desktop
MEOF
success "Standard-Anwendungen gesetzt"

# ── Berechtigungen ───────────────────────────────────────────
chown -R "$TARGET_USER:$TARGET_USER" "$CONFIG_DIR"
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/Pictures/wallpapers"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.gtkrc-2.0"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.bash_profile"

# ── DKMS-Hooks wiederherstellen ──────────────────────────────
for hook in "${DKMS_HOOKS[@]}"; do
    [[ -f "${hook}.snowfox-bak" ]] && mv "${hook}.snowfox-bak" "$hook"
done
info "DKMS-Hooks wiederhergestellt"

# ── Alte Kernel aufräumen ────────────────────────────────────
info "Bereinige alte Kernel..."
apt-get autoremove --purge -y 2>/dev/null || true
success "Alte Kernel entfernt"

# ============================================================
# Fertig!
# ============================================================
echo -e "${PURPLE}${BOLD}"
echo "  ███████╗███╗  ██╗ ██████╗ ██╗    ██╗███████╗ ██████╗ ██╗  ██╗"
echo "  ██╔════╝████╗ ██║██╔═══██╗██║    ██║██╔════╝██╔═══██╗╚██╗██╔╝"
echo "  ███████╗██╔██╗██║██║   ██║██║ █╗ ██║█████╗  ██║   ██║ ╚███╔╝ "
echo "  ╚════██║██║╚████║██║   ██║██║███╗██║██╔══╝  ██║   ██║ ██╔██╗ "
echo "  ███████║██║ ╚███║╚██████╔╝╚███╔███╔╝██║     ╚██████╔╝██╔╝╚██╗"
echo "  ╚══════╝╚═╝  ╚══╝ ╚═════╝  ╚══╝╚══╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝"
echo -e "${RESET}"
success "SnowFoxOS v2.1 erfolgreich installiert!"
warn   "Bitte neu starten: sudo reboot"
