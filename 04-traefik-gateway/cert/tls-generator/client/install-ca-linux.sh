#!/usr/bin/env bash
set -Eeuo pipefail

################################################################################
# CLIENT-SIDE ROOT CA INSTALLER FOR LINUX
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CA_CERT="${SCRIPT_DIR}/rootCA.crt"
CERT_NAME="avgol-internal-root-ca.crt"

echo "================================================================="
echo " Installing Internal Root CA on Linux"
echo "================================================================="

# Check root privileges
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run this script with sudo or as root:"
    echo "  sudo $0"
    exit 1
fi

# Check certificate file exists
if [ ! -f "${CA_CERT}" ]; then
    echo "ERROR: Root CA certificate not found at:"
    echo "  ${CA_CERT}"
    echo "Please make sure 'rootCA.crt' is in the same directory as this script."
    exit 1
fi

# Detect OS family
if [ -d "/usr/local/share/ca-certificates" ]; then
    # Debian / Ubuntu / Mint / PopOS
    echo "Detected Debian/Ubuntu system..."
    cp "${CA_CERT}" "/usr/local/share/ca-certificates/${CERT_NAME}"
    update-ca-certificates
    echo "✔ Root CA installed and trusted system-wide!"

elif [ -d "/etc/pki/ca-trust/source/anchors" ]; then
    # RHEL / CentOS / Rocky / AlmaLinux / Fedora
    echo "Detected RHEL/CentOS/Fedora system..."
    cp "${CA_CERT}" "/etc/pki/ca-trust/source/anchors/${CERT_NAME}"
    update-ca-trust extract
    echo "✔ Root CA installed and trusted system-wide!"

elif [ -d "/etc/ca-certificates/trust-source/anchors" ]; then
    # Arch Linux / Manjaro
    echo "Detected Arch Linux system..."
    cp "${CA_CERT}" "/etc/ca-certificates/trust-source/anchors/${CERT_NAME}"
    trust extract-compat
    echo "✔ Root CA installed and trusted system-wide!"

else
    echo "ERROR: Unsupported Linux distribution. Please manually install ${CA_CERT} to your system trust store."
    exit 1
fi

echo "================================================================="
echo " Complete! Restart browsers/applications to apply trust."
echo "================================================================="
