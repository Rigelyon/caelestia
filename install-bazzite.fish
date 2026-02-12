#!/usr/bin/env fish

# --- BAZZITE EDITION ---
# Script ini dimodifikasi khusus untuk Bazzite/Fedora Atomic.
# Dependencies (cli, python libs, quickshell binary) diasumsikan sudah ada di Image.
# Script ini fokus pada: Symlink Config & Clone Repo Shell.

argparse -n 'install.fish' -X 0 \
    'h/help' \
    'noconfirm' \
    'zen' \
    -- $argv
or exit

# Print help
if set -q _flag_h
    echo 'usage: ./install-bazzite.fish [-h] [--noconfirm]'
    echo
    echo 'NOTE: Dependencies (quickshell, caelestia-cli) must be installed via Bazzite Image.'
    echo 'This script links configuration files and clones the shell repo.'
    exit
end

# Helper funcs
function _out -a colour text
    set_color $colour
    echo $argv[3..] -- ":: $text"
    set_color normal
end

function log -a text
    _out cyan $text $argv[2..]
end

function input -a text
    _out blue $text $argv[2..]
end

function sh-read
    sh -c 'read a && echo -n "$a"' || exit 1
end

function confirm-overwrite -a path
    if test -e $path -o -L $path
        if set -q _flag_noconfirm
            input "$path already exists. Overwrite? [Y/n]"
            log 'Removing...'
            rm -rf $path
        else
            input "$path already exists. Overwrite? [Y/n] " -n
            set -l confirm (sh-read)
            if test "$confirm" = 'n' -o "$confirm" = 'N'
                log 'Skipping...'
                return 1
            else
                log 'Removing...'
                rm -rf $path
            end
        end
    end
    return 0
end

# Variables
set -q XDG_CONFIG_HOME && set -l config $XDG_CONFIG_HOME || set -l config $HOME/.config
set -q XDG_STATE_HOME && set -l state $XDG_STATE_HOME || set -l state $HOME/.local/state

# Startup prompt
set_color magenta
echo '╭─────────────────────────────────────────────────╮'
echo '│      CAELESTIA DOTFILES (BAZZITE EDITION)       │'
echo '╰─────────────────────────────────────────────────╯'
set_color normal
log 'Ensure you are running this on the Bazzite Custom Image you built.'

# Prompt for backup
if ! set -q _flag_noconfirm
    log '[1] Two steps ahead of you!  [2] Make one for me please!'
    input '=> ' -n
    set -l choice (sh-read)

    if contains -- "$choice" 1 2
        if test $choice = 2
            log "Backing up $config..."
            if test -e $config.bak
                rm -rf $config.bak
            end
            cp -r $config $config.bak
        end
    else
        log 'No choice selected. Exiting...'
        exit 1
    end
end

function install_caelestia_shell
    set_color green; echo "🚀 Memulai Setup Caelestia Shell via Distrobox..."; set_color normal

    # 1. Cek apakah Distrobox 'caelestia-box' sudah ada, jika belum buat baru
    if not distrobox list | grep -q "caelestia-box"
        echo "📦 Membuat container Arch Linux untuk build environment..."
        # Kita pakai Arch karena dokumentasi Caelestia aslinya berbasis Arch
        distrobox create --name caelestia-box --image archlinux:latest --yes
    end

    # 2. Jalankan perintah build DI DALAM container
    echo "🔨 Menginstall dependencies dan compiling..."
    
    distrobox enter caelestia-box -- sh -c '
        # A. Install Dependencies (Arch pacman)
        # --noconfirm agar tidak tanya yes/no
        sudo pacman -Syu --noconfirm base-devel git cmake ninja \
            qt6-base qt6-declarative qt6-svg qt6-5compat \
            pipewire pipewire-jack libqalculate unzip wget

        # B. Persiapan Folder
        mkdir -p ~/Sources
        cd ~/Sources
        rm -rf shell # Hapus sisa build lama jika ada

        # C. Clone Repository
        echo "📥 Cloning Caelestia Shell..."
        git clone https://github.com/caelestia-dots/shell.git
        cd shell

        # D. Fix Versioning (Masalah git describe tadi)
        git config --global user.email "builder@localhost"
        git config --global user.name "Builder"
        git tag -a v1.0.0 -m "Release 1.0.0" || true

        # E. Build & Install
        # Kita install ke $HOME/.local agar binary-nya muncul di Host juga
        echo "⚙️ Compiling..."
        cmake -B build -G Ninja -DCMAKE_INSTALL_PREFIX=$HOME/.local -DCMAKE_BUILD_TYPE=Release
        cmake --build build
        cmake --install build
        
        echo "✅ Build Selesai!"
    '

    set_color green; echo "🎉 Caelestia Shell berhasil diinstall!"; set_color normal
    echo "Silakan logout dan login kembali, atau jalankan langsung."
end

# --- EKSEKUSI FUNGSI ---
install_caelestia_shell

# Cd into dir
cd (dirname (status filename)) || exit 1

# --- BAGIAN 1: INSTALL CONFIG (SYMLINK BIASA) ---

# Install hypr* configs
if confirm-overwrite $config/hypr
    log 'Installing hypr* configs...'
    ln -s (realpath hypr) $config/hypr
end

# Starship
if confirm-overwrite $config/starship.toml
    log 'Installing starship config...'
    ln -s (realpath starship.toml) $config/starship.toml
end

# Foot
if confirm-overwrite $config/foot
    log 'Installing foot config...'
    ln -s (realpath foot) $config/foot
end

# Fish
if confirm-overwrite $config/fish
    log 'Installing fish config...'
    ln -s (realpath fish) $config/fish
end

# Fastfetch
if confirm-overwrite $config/fastfetch
    log 'Installing fastfetch config...'
    ln -s (realpath fastfetch) $config/fastfetch
end

# Uwsm (Jika pakai uwsm)
if confirm-overwrite $config/uwsm
    log 'Installing uwsm config...'
    ln -s (realpath uwsm) $config/uwsm
end

# Btop
if confirm-overwrite $config/btop
    log 'Installing btop config...'
    ln -s (realpath btop) $config/btop
end

# --- BAGIAN 2: QUICKSHELL (SETUP KHUSUS) ---
# Kita tidak symlink folder 'quickshell' lokal, tapi clone repo shell.
# Struktur target: ~/.config/quickshell/caelestia

set -l qs_config "$config/quickshell"
set -l shell_repo_path "$qs_config/caelestia"

log 'Setting up Caelestia Shell (Quickshell)...'

# Buat folder induk quickshell jika belum ada
if not test -d $qs_config
    mkdir -p $qs_config
end

# Clone atau Update repo shell
if test -d $shell_repo_path
    log 'Caelestia Shell repo found. Updating...'
    cd $shell_repo_path
    git pull
    cd -
else
    log 'Cloning Caelestia Shell repo...'
    git clone https://github.com/caelestia-dots/shell.git $shell_repo_path
    if test $status -ne 0
        set_color red
        echo ":: ERROR: Failed to clone shell repo. Check your internet connection."
        set_color normal
    end
end

# Buat config user untuk shell (shell.json) jika belum ada
# File ini memberitahu quickshell modul apa yang harus diload
set -l caelestia_conf "$config/caelestia"
set -l shell_json "$caelestia_conf/shell.json"

if not test -d $caelestia_conf
    mkdir -p $caelestia_conf
end

if not test -f $shell_json
    log 'Creating default shell.json...'
    # Konfigurasi default: aktifkan status-bar
    echo '{
    "use-hyprland-ipc": true,
    "modules": {
        "status-bar": { "visible": true },
        "dashboard": { "visible": false }
    }
}' > $shell_json
end


# --- BAGIAN 3: APLIKASI TAMBAHAN ---

# 1. VS CODE (Asumsi: Layered RPM dari Image)
# Jika user menambahkan flag --vscode, kita hanya symlink config.
if set -q _flag_vscode
    log 'Configuring VS Code (RPM version)...'
    
    # Tentukan varian (Code atau Codium)
    # Di Bazzite biasanya 'code' (official) atau 'codium' tergantung image Anda.
    if type -q code
        set -l prog 'code'
        set -l folder 'Code'
    else if type -q codium
        set -l prog 'codium'
        set -l folder 'VSCodium'
    else
        log 'WARNING: VS Code/Codium not found in system path.'
        log 'Please layer it in your build.sh first.'
        set -l prog 'skip'
    end

    if test "$prog" != 'skip'
        set -l target_dir "$config/$folder/User"
        mkdir -p $target_dir
        
        # Symlink Settings
        if confirm-overwrite "$target_dir/settings.json"
            ln -s (realpath vscode/settings.json) "$target_dir/settings.json"
        end
        
        # Symlink Keybindings
        if confirm-overwrite "$target_dir/keybindings.json"
            ln -s (realpath vscode/keybindings.json) "$target_dir/keybindings.json"
        end
        
        log "VS Code configured. Install extensions manually or via CLI."
    end
end

# 2. DISCORD (Vesktop Flatpak)
# Kita ganti logika 'discord + patch' menjadi 'vesktop config'.
if set -q _flag_discord
    log 'Configuring Discord (Vesktop Flatpak)...'
    
    # Path config Vesktop (Vencord)
    set -l vesktop_conf "$HOME/.var/app/dev.vencord.Vesktop/config/vesktop"
    
    if test -d (dirname $vesktop_conf)
        mkdir -p $vesktop_conf
        
        # Jika Anda punya themes khusus untuk Vencord di repo dotfiles
        # Contoh: ln -s (realpath discord/themes) $vesktop_conf/themes
        log 'Vesktop folder detected. You can link your Vencord themes here.'
    else
        log 'Vesktop Flatpak not installed or not run yet. Skipping...'
    end
end

# 3. SPOTIFY (Spicetify on Flatpak)
if set -q _flag_spotify
    log 'Configuring Spotify (Spicetify for Flatpak)...'
    
    # Cek apakah Spotify Flatpak terinstall
    if not flatpak list | grep -q com.spotify.Client
        log 'Spotify Flatpak not found. Skipping...'
    else
        # 1. Install Spicetify CLI (Local User) jika belum ada
        if not type -q spicetify
            log 'Installing Spicetify CLI...'
            curl -fsSL https://spicetify.app/install.sh | sh
            # Tambahkan ke path sementara agar bisa dipanggil
            set -x PATH $HOME/.spicetify $PATH
        end

        # 2. Beri izin Flatpak (Wajib untuk Spicetify)
        log 'Granting Flatpak permissions...'
        flatpak override --user --filesystem=xdg-config/spotify com.spotify.Client
        flatpak override --user --filesystem=$HOME/.spicetify com.spotify.Client

        # 3. Apply Config
        log 'Applying Spicetify...'
        # Setup path spicetify untuk flatpak
        spicetify config spotify_path $HOME/.var/app/com.spotify.Client/config/spotify
        spicetify config prefs_path $HOME/.var/app/com.spotify.Client/config/spotify/prefs
        
        # Symlink Tema Caelestia ke folder themes Spicetify
        set -l spice_themes "$HOME/.config/spicetify/Themes" # Lokasi default spicetify-cli
        mkdir -p $spice_themes
        
        if test -d "spicetify/Themes/caelestia"
            rm -rf "$spice_themes/caelestia"
            ln -s (realpath spicetify/Themes/caelestia) "$spice_themes/caelestia"
            
            spicetify config current_theme caelestia
            spicetify config color_scheme caelestia
            spicetify config inject_css 1 replace_colors 1 overwrite_assets 1
            
            # Backup & Apply
            spicetify backup apply
        else
             log 'Caelestia Spicetify theme not found in current dir.'
        end
    end
end

# 4. ZEN BROWSER (Flatpak)
if set -q _flag_zen
    log 'Configuring Zen Browser (Flatpak)...'
    
    # Cari path random profile Zen Flatpak
    # Lokasi: ~/.var/app/app.zen_browser.zen/.zen/[random].default
    set -l zen_flatpak_root "$HOME/.var/app/app.zen_browser.zen/.zen"
    
    if test -d $zen_flatpak_root
        # Ambil folder profile pertama yang ditemukan
        set -l profile_dir (find $zen_flatpak_root -maxdepth 1 -type d -name "*.default*" | head -n 1)
        
        if test -n "$profile_dir"
            log "Found Zen profile: $profile_dir"
            set -l chrome_dir "$profile_dir/chrome"
            mkdir -p $chrome_dir
            
            # Symlink userChrome.css
            if confirm-overwrite "$chrome_dir/userChrome.css"
                # Asumsi file ada di folder 'zen' repo Anda
                ln -s (realpath zen/userChrome.css) "$chrome_dir/userChrome.css"
                log 'userChrome.css installed.'
            end
        else
            log 'No Zen profile folder found. Please open Zen once first.'
        end
    else
        log 'Zen Flatpak directory not found.'
    end
end


# --- BAGIAN 4: POST INSTALL (THEMING) ---

log 'Finalizing setup...'

# Pastikan caelestia-cli terinstall (seharusnya sudah ada di Image Bazzite)
if type -q caelestia
    log 'Applying Caelestia theme (shadotheme)...'
    
    # Cek apakah scheme json sudah ada, jika tidak generate baru
    if ! test -f $state/caelestia/scheme.json
        caelestia scheme set -n shadotheme
    else
        # Force update agar sinkron
        caelestia scheme set -n shadotheme --update
    end
    
    # Reload hyprland jika sedang jalan
    if pidof Hyprland > /dev/null
         hyprctl reload
    end
else
    set_color red
    echo ":: WARNING: 'caelestia' command not found!"
    echo ":: Please ensure you added the pip install step in your Bazzite build.sh."
    set_color normal
end

log 'Done! Please restart Hyprland (Super+M usually) to start Quickshell.'s