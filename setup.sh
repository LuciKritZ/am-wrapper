#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TOTAL_STEPS=6
CURRENT_STEP=1

print_step() {
    echo -e "\n${BLUE}[${CURRENT_STEP}/${TOTAL_STEPS}]${NC} ${GREEN}$1${NC}"
    CURRENT_STEP=$((CURRENT_STEP + 1))
}

echo -e "${BLUE}This script requires superuser permissions (sudo) to install dependencies and configure the systemd service.${NC}"
# Clear any cached sudo credentials to ensure the user is explicitly prompted
sudo -k
# Prompt for sudo password upfront
sudo -v
# Keep sudo alive in the background while the script runs (prevents timeout during long builds)
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

print_step "Installing dependencies..."
MISSING_DEPS=""
if ! command -v gcc >/dev/null 2>&1; then MISSING_DEPS="$MISSING_DEPS build-essential"; fi
if ! command -v cmake >/dev/null 2>&1; then MISSING_DEPS="$MISSING_DEPS cmake"; fi
if ! command -v curl >/dev/null 2>&1; then MISSING_DEPS="$MISSING_DEPS curl"; fi
if ! command -v unzip >/dev/null 2>&1; then MISSING_DEPS="$MISSING_DEPS unzip"; fi
if ! command -v git >/dev/null 2>&1; then MISSING_DEPS="$MISSING_DEPS git"; fi

if [ -n "$MISSING_DEPS" ]; then
    echo "Missing dependencies:$MISSING_DEPS"
    
    update_apt=""
    while [[ ! "$update_apt" =~ ^[YyNn]$ ]]; do
        echo "Do you want to run 'sudo apt update' before installing? (y/n):"
        read -r update_apt </dev/tty
    done
    
    if [[ "$update_apt" =~ ^[Yy]$ ]]; then
        sudo apt update
    fi
    
    sudo apt install -y $MISSING_DEPS
else
    echo "Dependencies are already installed. Skipping..."
fi

print_step "Installing LLVM..."
if command -v clang >/dev/null 2>&1 || command -v llvm-config >/dev/null 2>&1 || ls /usr/bin/clang-* >/dev/null 2>&1; then
    install_llvm=""
    while [[ ! "$install_llvm" =~ ^[YyNn]$ ]]; do
        echo "A version of LLVM/Clang is already installed on your system."
        echo "Do you still want to run the official LLVM installation script? (y/n):"
        read -r install_llvm </dev/tty
    done
    if [[ "$install_llvm" =~ ^[Yy]$ ]]; then
        sudo bash -c "$(wget -O - https://apt.llvm.org/llvm.sh)"
    else
        echo "Skipping LLVM installation..."
    fi
else
    install_llvm=""
    while [[ ! "$install_llvm" =~ ^[YyNn]$ ]]; do
        echo "LLVM/Clang was not detected in your PATH. Do you want to install it using the official script? (y/n):"
        read -r install_llvm </dev/tty
    done
    if [[ "$install_llvm" =~ ^[Yy]$ ]]; then
        sudo bash -c "$(wget -O - https://apt.llvm.org/llvm.sh)"
    else
        echo "Skipping LLVM installation..."
    fi
fi

print_step "Downloading and extracting Android NDK..."
if [ ! -d "android-ndk-r23b" ]; then
    if [ ! -f "android-ndk-r23b-linux.zip" ]; then
        echo "Downloading Android NDK..."
        curl -fLO https://dl.google.com/android/repository/android-ndk-r23b-linux.zip
    fi
    echo "Extracting..."
    unzip -q -d . android-ndk-r23b-linux.zip
fi

print_step "Building wrapper..."
rm -rf build
mkdir build
cd build

echo "Configuring build with CMake..."
cmake .. > cmake.log 2>&1 || { echo -e "\nCMake failed! See build/cmake.log"; exit 1; }

echo "Compiling wrapper..."
make -j$(nproc) 2>&1 | awk '
/\[ *[0-9]+%\]/ {
    match($0, /\[ *[0-9]+%\]/);
    pstr = substr($0, RSTART+1, RLENGTH-3);
    gsub(/ /, "", pstr);
    p = pstr + 0;
    bars = int(p / 2);
    printf "\r\033[K\033[0;34m[\033[0;32m";
    for(i=0;i<bars;i++) printf "━";
    printf "\033[0;37m";
    for(i=bars;i<50;i++) printf "━";
    printf "\033[0;34m] \033[0;32m%d%%\033[0m", p;
}
END { print "" }'
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "\nCompilation failed! Try running '\''make'\'' manually in the build folder."
    exit 1
fi
cd ../

chmod +x wrapper

print_step "Initial login..."
am_username=""
am_password=""

# Load credentials from .env if the file exists
if [ -f ".env" ]; then
    source .env
    am_username="$USERNAME"
    am_password="$PASSWORD"
fi

while [[ -z "$am_username" ]]; do
    echo "Please enter your Apple Music username:"
    read -r am_username </dev/tty
done

while [[ -z "$am_password" ]]; do
    echo "Please enter your Apple Music password:"
    read -rs am_password </dev/tty
    echo
done

echo "Starting wrapper..."
touch wrapper_setup.log
sudo ./wrapper -L "${am_username}:${am_password}" -F > wrapper_setup.log 2>&1 &
WRAPPER_PID=$!

echo "Waiting for wrapper to initialize..."
NEEDS_2FA=0

# Monitor the wrapper output to see if 2FA is needed or if login succeeded
while read -r line; do
    echo "$line"
    if [[ "$line" == *"Please enter your 2FA code:"* ]]; then
        NEEDS_2FA=1
        break
    elif [[ "$line" == *"listening "* ]]; then
        break
    elif [[ "$line" == *"login failed"* ]]; then
        echo "Login failed. Please check your credentials."
        sudo pkill -f "./wrapper" 2>/dev/null || true
        exit 1
    fi
done < <(timeout 30s tail -f wrapper_setup.log)

if [ "$NEEDS_2FA" -eq 1 ]; then
    mfa_code=""
    while [[ -z "$mfa_code" ]]; do
        echo "Please enter your 2FA code:"
        read -r mfa_code </dev/tty
    done
    mkdir -p rootfs/data/data/com.apple.android.music/files
    echo -n "$mfa_code" > rootfs/data/data/com.apple.android.music/files/2fa.txt

    echo "Waiting for login to complete..."
    while [ -f "rootfs/data/data/com.apple.android.music/files/2fa.txt" ]; do
        sleep 1
    done
    sleep 5
else
    echo "Login successful without manual 2FA!"
    sleep 2
fi

sudo pkill -f "./wrapper" 2>/dev/null || true
rm -f wrapper_setup.log

print_step "Setting up systemd service..."

if [ -f "/etc/systemd/system/am-wrapper.service" ]; then
    echo "Existing service found. Stopping and updating..."
    sudo systemctl stop am-wrapper || true
fi

echo "Writing service file..."
cat <<EOF | sudo tee /etc/systemd/system/am-wrapper.service > /dev/null
[Unit]
Description=Apple Music Wrapper
After=network.target

[Service]
Type=simple
WorkingDirectory=$PWD
ExecStart=$PWD/wrapper -H 0.0.0.0
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
echo "Enabling am-wrapper service..."
sudo systemctl daemon-reload
sudo systemctl enable am-wrapper

echo "Restarting am-wrapper service..."
sudo systemctl restart am-wrapper

echo -e "\n${GREEN}Setup complete! The service is now running.${NC}"
