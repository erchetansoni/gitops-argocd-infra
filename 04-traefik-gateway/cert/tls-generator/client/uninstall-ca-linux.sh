#!/usr/bin/env bash
set -Eeuo pipefail

################################################################################
# CLIENT-SIDE ROOT CA UNINSTALLER FOR LINUX
################################################################################

CERT_NAME="avgol-internal-root-ca.crt"

echo "================================================================="
echo " Removing Internal Root CA from Linux Trust Store"
echo "================================================================="

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run this script with sudo or as root:"
    echo "  sudo $0"
    exit 1
fi

if [ -f "/usr/local/share/ca-certificates/${CERT_NAME}" ]; then
    rm -f "/usr/local/share/ca-certificates/${CERT_NAME}"
    update-ca-certificates --fresh
    echo "✔ Root CA removed from Debian/Ubuntu trust store!"

elif [ -f "/etc/pki/ca-trust/source/anchors/${CERT_NAME}" ]; then
    rm -f "/etc/pki/ca-trust/source/anchors/${CERT_NAME}"
    update-ca-trust extract
    echo "✔ Root CA removed from RHEL/CentOS trust store!"

elif [ -f "/etc/ca-certificates/trust-source/anchors/${CERT_NAME}" ]; then
    rm -f "/etc/ca-certificates/trust-source/anchors/${CERT_NAME}"
    trust extract-compat
    echo "✔ Root CA removed from Arch Linux trust store!"

else
    echo "[*] No certificate named '${CERT_NAME}' was found in standard CA locations."
fi

echo "================================================================="
echo " Complete!"
echo "================================================================="
