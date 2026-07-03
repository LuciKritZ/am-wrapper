#!/bin/bash
set -e

REPO_URL="https://github.com/LuciKritZ/am-wrapper.git"
INSTALL_DIR="$HOME/.am-wrapper"

echo "======================================"
echo "    am-wrapper Installation Script    "
echo "======================================"

echo "Cloning am-wrapper into $INSTALL_DIR..."
if [ -d "$INSTALL_DIR" ]; then
    echo "Directory $INSTALL_DIR already exists. Updating..."
    cd "$INSTALL_DIR"
    git pull
else
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

echo "Starting setup..."
bash setup.sh
