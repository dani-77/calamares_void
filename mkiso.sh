#!/bin/bash

set -eu

. ./lib.sh

PROGNAME=$(basename "$0")
ARCH=$(uname -m)
IMAGES="base dwm fluxbox hyprland labwc openbox qtile sway"
TRIPLET=
REPO=
DATE=$(date -u +%Y%m%d)

usage() {
	cat <<-EOH
	Usage: $PROGNAME [options ...] [-- mklive options ...]

	Wrapper script around mklive.sh for several standard flavors of live images.
	Adds d77void-installer and other helpful utilities to the generated images.
        
	adaptation of mkiso.sh by Daniel Azevedo (dani-77) 

	OPTIONS
	 -a <arch>     Set architecture (or platform) in the image
	 -b <variant>  One of base, dwm, fluxbox, hyprland, labwc, openbox or sway. 
               May be specified multiple times to build multiple variants.
	 -d <date>     Override the datestamp on the generated image (YYYYMMDD format)
	 -t <arch-date-variant>
	               Equivalent to setting -a, -b, and -d
	 -r <repo>     Use this XBPS repository. May be specified multiple times
	 -h            Show this help and exit
	 -V            Show version and exit

	Other options can be passed directly to mklive.sh by specifying them after the --.
	See mklive.sh -h for more details.
	EOH
}

while getopts "a:b:d:t:hr:V" opt; do
case $opt in
    a) ARCH="$OPTARG";;
    b) IMAGES="$OPTARG";;
    d) DATE="$OPTARG";;
    r) REPO="-r $OPTARG $REPO";;
    t) TRIPLET="$OPTARG";;
    V) version; exit 0;;
    h) usage; exit 0;;
    *) usage >&2; exit 1;;
esac
done
shift $((OPTIND - 1))

INCLUDEDIR=$(mktemp -d)
trap "cleanup" INT TERM

cleanup() {
    rm -rf "$INCLUDEDIR"
}

include_installer() {
    if [ -x installer.sh ]; then
        MKLIVE_VERSION="$(PROGNAME='' version)"
        installer=$(mktemp)
        sed "s/@@MKLIVE_VERSION@@/${MKLIVE_VERSION}/" installer.sh > "$installer"
        install -Dm755 "$installer" "$INCLUDEDIR"/usr/bin/d77void-installer
        rm "$installer"
    else
        echo installer.sh not found >&2
        exit 1
    fi
}

setup_pipewire() {
    PKGS="$PKGS pipewire alsa-pipewire"
    case "$ARCH" in
        asahi*)
            PKGS="$PKGS asahi-audio"
            SERVICES="$SERVICES speakersafetyd"
            ;;
    esac
    mkdir -p "$INCLUDEDIR"/etc/xdg/autostart
    ln -sf /usr/share/applications/pipewire.desktop "$INCLUDEDIR"/etc/xdg/autostart/
    mkdir -p "$INCLUDEDIR"/etc/pipewire/pipewire.conf.d
    ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf "$INCLUDEDIR"/etc/pipewire/pipewire.conf.d/
    ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf "$INCLUDEDIR"/etc/pipewire/pipewire.conf.d/
    mkdir -p "$INCLUDEDIR"/etc/alsa/conf.d
    ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf "$INCLUDEDIR"/etc/alsa/conf.d
    ln -sf /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf "$INCLUDEDIR"/etc/alsa/conf.d
}

include_common() {
	mkdir -p "$INCLUDEDIR"/etc
	mkdir -p "$INCLUDEDIR"/etc/default
	mkdir -p "$INCLUDEDIR"/usr/bin
	mkdir -p "$INCLUDEDIR"/usr/share/polkit-1/rules.d
	mkdir -p "$INCLUDEDIR"/usr/share/void-artwork
	mkdir -p "$INCLUDEDIR"/usr/share/sddm/faces
	mkdir -p "$INCLUDEDIR"/usr/share/sddm/themes
	cp -r ./common/calamares "$INCLUDEDIR"/etc/
	cp -r $variant/skel "$INCLUDEDIR"/etc/
	cp ./common/sddm.conf "$INCLUDEDIR"/etc/
	cp ./common/grub "$INCLUDEDIR"/etc/default/
	cp ./common/rofi-power-menu "$INCLUDEDIR"/usr/bin/
	cp ./common/50-udisks.rules "$INCLUDEDIR"/usr/share/polkit-1/rules.d/
	cp ./common/splash.png "$INCLUDEDIR"/usr/share/void-artwork/
	cp ./common/anon.face.icon "$INCLUDEDIR"/usr/share/sddm/faces/
	cp -r ./common/slice "$INCLUDEDIR"/usr/share/sddm/themes/
}

include_way() {
	cp ./common/wswap-way "$INCLUDEDIR"/usr/bin/
}	

include_x11() {
	cp ./common/wswap-X "$INCLUDEDIR"/usr/bin/
}	

include_dwm() {
	mkdir -p "$INCLUDEDIR"/usr/bin
	cp $variant/power_menu "$INCLUDEDIR"/usr/bin/
}

build_variant() {
    variant="$1"
    shift
    IMG=d77void-live-${ARCH}-${DATE}-${variant}.iso

    # el-cheapo installer is unsupported on arm because arm doesn't install a kernel by default
    # and to work around that would add too much complexity to it
    # thus everyone should just do a chroot install anyways
    WANT_INSTALLER=no
    case "$ARCH" in
        x86_64*|i686*)
            GRUB_PKGS="grub-i386-efi grub-x86_64-efi"
            GFX_PKGS="xorg-video-drivers"
            GFX_WL_PKGS="mesa-dri"
            WANT_INSTALLER=yes
            TARGET_ARCH="$ARCH"
            CALAMARES="calamares grub rsync"
	    COMMON=
	    X11=
	    WAY=
	    DWM=
	    ;;
        aarch64*)
            GRUB_PKGS="grub-arm64-efi"
            GFX_PKGS="xorg-video-drivers"
            GFX_WL_PKGS="mesa-dri"
            TARGET_ARCH="$ARCH"
            ;;
        asahi*)
            GRUB_PKGS="asahi-base asahi-scripts grub-arm64-efi"
            GFX_PKGS="mesa-asahi-dri"
            GFX_WL_PKGS="mesa-asahi-dri"
            KERNEL_PKG="linux-asahi"
            TARGET_ARCH="aarch64${ARCH#asahi}"
            if [ "$variant" = xfce ]; then
                info_msg "xfce is not supported on asahi, switching to xfce-wayland"
                variant="xfce-wayland"
            fi
            ;;
    esac

    A11Y_PKGS="espeakup void-live-audio brltty"
    PKGS="dialog cryptsetup lvm2 mdadm void-docs-browse xtools-minimal xmirror chrony tmux $A11Y_PKGS $GRUB_PKGS"
    FONTS="font-misc-misc terminus-font dejavu-fonts-ttf"
    WAYLAND_PKGS="$GFX_WL_PKGS $FONTS orca"
    XORG_PKGS="$GFX_PKGS $FONTS xorg-minimal xorg-input-drivers setxkbmap xauth orca"
    SERVICES="sshd chronyd"

    LIGHTDM_SESSION=''

    case $variant in
        base)
            SERVICES="$SERVICES dhcpcd wpa_supplicant acpid"
        ;;
	dwm)
	    COMMON=yes
	    X11=yes
	    DWM=yes
            PKGS="$PKGS $XORG_PKGS $CALAMARES base-devel fontconfig-devel freetype-devel gcr-devel gcr4-devel glibc-devel gtk+3-devel harfbuzz-devel imlib2-devel libX11-devel libXft-devel libXinerama-devel webkit2gtk-devel abiword acpi apulse alsa-plugins-pulseaudio alsa-tools alsa-utils arc-theme bash-completion bc ca-certificates cmus cups cups-browsed curl dmenu dunst elogind epson-inkjet-printer-escpr ethtool feh firefox font-awesome font-awesome5 font-awesome6 font-hack-ttf geary gettext git github-cli gmrun gnumeric htop inxi lxappearance mousepad mpv nano ncspot NetworkManager nerd-fonts-symbols-ttf neofetch nextcloud-client octoxbps papirus-icon-theme pcmanfm polkit pcsc-ccid pcsc-tools pcsclite ranger redshift rofi scrot sddm slock smartmontools sxhkd tlp tlp-rdw transmission-gtk transset udiskie ueberzug ufw uget unzip usbutils util-linux vim void-repo-multilib void-repo-multilib-nonfree void-repo-nonfree wget xautolock xcompmgr xdg-user-dirs xdg-user-dirs-gtk xdg-utils xf86-input-synaptics xarchiver xcalc xinit xorg xorg-server xpdf xterm yt-dlp zathura zathura-pdf-poppler"
            SERVICES="$SERVICES dbus elogind sddm NetworkManager polkitd"
        ;;
	fluxbox)
	    COMMON=yes
	    X11=yes
            PKGS="$PKGS $XORG_PKGS $CALAMARES abiword acpi apulse alsa-plugins-pulseaudio alsa-tools alsa-utils arc-theme bash-completion bc ca-certificates cbatticon cmus conky cups cups-browsed curl dunst elogind epson-inkjet-printer-escpr ethtool feh firefox fluxbox font-hack-ttf geary gettext git github-cli gmrun gnumeric htop inxi jgmenu jq lxappearance mousepad mpv nano ncspot NetworkManager network-manager-applet nerd-fonts-symbols-ttf neofetch nextcloud-client octoxbps papirus-icon-theme pass pcmanfm polkit pcsc-ccid pcsc-tools pcsclite ranger redshift redshift-gtk rofi scrot slim slock smartmontools system-config-printer tlp tlp-rdw transmission-gtk transset udiskie ueberzug ufw uget unzip usbutils util-linux vim void-repo-multilib void-repo-multilib-nonfree void-repo-nonfree volumeicon wget xautolock xcompmgr xdg-user-dirs xdg-user-dirs-gtk xdg-utils xf86-input-synaptics xarchiver xcalc xinit xorg xorg-server xpdf xterm yt-dlp zathura zathura-pdf-poppler"
            SERVICES="$SERVICES dbus elogind sddm NetworkManager polkitd"
        ;;
	hyprland)
	    COMMON=yes
	    WAY=yes
            PKGS="$PKGS $XORG_PKGS $WAYLAND_PKGS $CALAMARES acpi apulse alsa-plugins-pulseaudio alsa-tools alsa-utils arc-theme bash-completion bc brightnessctl ca-certificates cups cups-browsed curl elogind epson-inkjet-printer-escpr ethtool feh firefox font-awesome6 font-hack-ttf geary gettext git github-cli gmrun grim htop hyprland ImageMagick inxi kitty lxappearance mousepad mpv nano ncspot NetworkManager network-manager-applet nerd-fonts-symbols-ttf neofetch nextcloud-client octoxbps papirus-icon-theme pavucontrol pcmanfm polkit qt6-wayland ranger rofi sddm smartmontools swaybg swayidle swayimg swaylock SwayNotificationCenter system-config-printer tlp tlp-rdw transmission-gtk udiskie ueberzug ufw uget unzip usbutils util-linux vim void-repo-multilib void-repo-multilib-nonfree void-repo-nonfree wayland-devel wayland-protocols Waybar wget wlsunset wmenu xdg-user-dirs xdg-user-dirs-gtk xdg-utils xf86-input-synaptics xarchiver xcalc xorg-server-xwayland xpdf xterm yt-dlp zathura zathura-pdf-poppler"
            SERVICES="$SERVICES dbus elogind sddm NetworkManager polkitd"
        ;;
	labwc)
	    COMMON=yes
	    WAY=yes
            PKGS="$PKGS $XORG_PKGS $WAYLAND_PKGS $CALAMARES abiword acpi apulse alsa-plugins-pulseaudio alsa-tools alsa-utils arc-theme bash-completion bc brightnessctl ca-certificates cups cups-browsed curl elogind epson-inkjet-printer-escpr ethtool feh firefox font-awesome6 font-hack-ttf geary gettext git github-cli gmrun gnumeric grim htop ImageMagick inxi kitty labwc labwc-menu-generator labwc-tweaks-qt lxappearance mousepad mpv nano ncspot NetworkManager network-manager-applet nerd-fonts-symbols-ttf neofetch nextcloud-client octoxbps papirus-icon-theme pcmanfm polkit pcsc-ccid pcsc-tools pcsclite ranger rofi sddm sfwbar smartmontools swaybg swayidle swayimg swaylock SwayNotificationCenter system-config-printer tlp tlp-rdw transmission-gtk udiskie ueberzug ufw uget unzip usbutils util-linux vim void-repo-multilib void-repo-multilib-nonfree void-repo-nonfree Waybar wget wlsunset xdg-user-dirs xdg-user-dirs-gtk xdg-utils xf86-input-synaptics xarchiver xcalc xpdf xterm yt-dlp zathura zathura-pdf-poppler"
            SERVICES="$SERVICES dbus elogind sddm NetworkManager polkitd"
        ;;
	openbox)
	    COMMON=yes
	    X11=yes
            PKGS="$PKGS $XORG_PKGS $CALAMARES abiword acpi apulse alsa-plugins-pulseaudio alsa-tools alsa-utils arc-theme bash-completion bc ca-certificates cbatticon cmus conky cups cups-browsed curl dunst elogind epson-inkjet-printer-escpr ethtool feh firefox font-hack-ttf geary gettext git github-cli gmrun gnumeric htop inxi jgmenu jq lxappearance lxappearance-obconf menumaker mousepad mpv nano ncspot NetworkManager network-manager-applet nerd-fonts-symbols-ttf neofetch nextcloud-client obconf octoxbps openbox papirus-icon-theme pcmanfm polkit pcsc-ccid pcsc-tools pcsclite ranger redshift redshift-gtk rofi scrot slim slock smartmontools sxhkd system-config-printer tint2 tint2conf tlp tlp-rdw transmission-gtk transset udiskie ueberzug ufw uget unzip usbutils util-linux vim void-repo-multilib void-repo-multilib-nonfree void-repo-nonfree volumeicon wget xautolock xcompmgr xdg-user-dirs xdg-user-dirs-gtk xdg-utils xf86-input-synaptics xarchiver xcalc xinit xorg xorg-server xpdf xterm yt-dlp zathura zathura-pdf-poppler"
            SERVICES="$SERVICES dbus elogind sddm NetworkManager polkitd"
        ;;        
	qtile)
	    COMMON=yes
	    WAY=yes
    	    PKGS="$PKGS $XORG_PKGS $WAYLAND_PKGS $CALAMARES abiword acpi apulse alsa-plugins-pulseaudio alsa-tools alsa-utils arc-theme bash-completion bc brightnessctl ca-certificates cups cups-browsed curl elogind epson-inkjet-printer-escpr ethtool feh firefox font-awesome6 font-hack-ttf geary gettext git github-cli gnumeric grim htop ImageMagick inxi kitty lxappearance mousepad mpv nano ncspot NetworkManager network-manager-applet nerd-fonts-symbols-ttf neofetch nextcloud-client octoxbps papirus-icon-theme pavucontrol pcmanfm polkit pcsc-ccid pcsc-tools pcsclite python3-qtile-extras qtile qtile-wayland ranger redshift rofi sddm smartmontools swaybg swaylock SwayNotificationCenter system-config-printer tlp tlp-rdw transmission-gtk udiskie ueberzug ufw uget unzip usbutils util-linux vim void-repo-multilib void-repo-multilib-nonfree void-repo-nonfree wget wlsunset xdg-user-dirs xdg-user-dirs-gtk xdg-utils xf86-input-synaptics xarchiver xcalc xpdf xterm yt-dlp zathura zathura-pdf-poppler"
            SERVICES="$SERVICES dbus elogind sddm NetworkManager polkitd"
        ;;
	sway)
	    COMMON=yes
	    WAY=yes
            PKGS="$PKGS $XORG_PKGS $WAYLAND_PKGS $CALAMARES abiword acpi apulse alsa-plugins-pulseaudio alsa-tools alsa-utils arc-theme bash-completion bc brightnessctl ca-certificates cups cups-browsed curl elogind epson-inkjet-printer-escpr ethtool feh firefox font-awesome6 font-hack-ttf geary gettext git github-cli gmrun gnumeric grim htop ImageMagick inxi kitty lxappearance mousepad mpv nano ncspot NetworkManager network-manager-applet nerd-fonts-symbols-ttf neofetch nextcloud-client octoxbps papirus-icon-theme pavucontrol pcmanfm polkit pcsc-ccid pcsc-tools pcsclite ranger rofi sddm smartmontools sway swaybg swayidle swayimg swaylock SwayNotificationCenter system-config-printer tlp tlp-rdw transmission-gtk udiskie ueberzug ufw uget unzip usbutils util-linux vim void-repo-multilib void-repo-multilib-nonfree void-repo-nonfree Waybar wget wlsunset wmenu xdg-user-dirs xdg-user-dirs-gtk xdg-utils xf86-input-synaptics xarchiver xcalc xpdf xterm yt-dlp zathura zathura-pdf-poppler"
            SERVICES="$SERVICES dbus elogind sddm NetworkManager polkitd"
        ;;
        *)
            >&2 echo "Unknown variant $variant"
            exit 1
        ;;
    esac

    if [ -n "$LIGHTDM_SESSION" ]; then
        mkdir -p "$INCLUDEDIR"/etc/lightdm
        echo "$LIGHTDM_SESSION" > "$INCLUDEDIR"/etc/lightdm/.session
        # needed to show the keyboard layout menu on the login screen
        cat <<- EOF > "$INCLUDEDIR"/etc/lightdm/lightdm-gtk-greeter.conf
[greeter]
indicators = ~host;~spacer;~clock;~spacer;~layout;~session;~a11y;~power
EOF
    fi

    if [ "$COMMON" = yes ]; then
        include_common
    fi

    if [ "$DWM" = yes ]; then
        include_dwm
    fi

    if [ "$X11" = yes ]; then
        include_x11
    fi

    if [ "$WAY" = yes ]; then
        include_way
    fi

    if [ "$WANT_INSTALLER" = yes ]; then
        include_installer
    else
        mkdir -p "$INCLUDEDIR"/usr/bin
        printf "#!/bin/sh\necho 'd77void-installer is not supported on this live image'\n" > "$INCLUDEDIR"/usr/bin/d77void-installer
        chmod 755 "$INCLUDEDIR"/usr/bin/d77void-installer
    fi

    if [ "$variant" != base ]; then
        setup_pipewire
    fi

    ./mklive.sh -a "$TARGET_ARCH" -o "$IMG" -p "$PKGS" -S "$SERVICES" -I "$INCLUDEDIR" \
        ${KERNEL_PKG:+-v $KERNEL_PKG} ${REPO} "$@"

	cleanup
}

if [ ! -x mklive.sh ]; then
    echo mklive.sh not found >&2
    exit 1
fi

if [ -n "$TRIPLET" ]; then
    IFS=: read -r ARCH DATE VARIANT _ < <( echo "$TRIPLET" | sed -Ee 's/^(.+)-([0-9rc]+)-(.+)$/\1:\2:\3/' )
    build_variant "$VARIANT" "$@"
else
    for image in $IMAGES; do
        build_variant "$image" "$@"
    done
fi
