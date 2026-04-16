#!/bin/bash
set -e

INSTALL_DIR="/usr/local/bin"
BINARY_NAME="ax-recorder"

echo "🔨 Budowanie ax-recorder..."

# Sprawdź czy swift jest dostępny
if ! command -v swift &> /dev/null; then
    echo "❌ Swift nie jest zainstalowany. Zainstaluj Xcode Command Line Tools:"
    echo "   xcode-select --install"
    exit 1
fi

# Build
swift build -c release 2>&1

BINARY=".build/release/$BINARY_NAME"

if [ ! -f "$BINARY" ]; then
    echo "❌ Budowanie nie powiodło się."
    exit 1
fi

# Install
echo "📦 Instalowanie do $INSTALL_DIR/$BINARY_NAME..."
if [ -w "$INSTALL_DIR" ]; then
    cp "$BINARY" "$INSTALL_DIR/$BINARY_NAME"
else
    sudo cp "$BINARY" "$INSTALL_DIR/$BINARY_NAME"
fi

chmod +x "$INSTALL_DIR/$BINARY_NAME"

echo ""
echo "✅ Zainstalowano! Użycie: ax-recorder"
echo ""
echo "⚠️  Pamiętaj o uprawnieniach Accessibility:"
echo "   System Settings → Privacy & Security → Accessibility → dodaj Terminal"
