#!/bin/sh

# Install a Hyperion x86_64 nightly build on LibreELEC/OpenELEC.
# An optional first argument may be used to provide a specific package URL.

set -eu

REPOSITORY="constantcharge/hyperion.ng"
RELEASE_TAG="nightly"
TARGET_DIRECTORY="/storage/hyperion"
SERVICE_NAME="hyperion@root.service"

if [ "$(id -u)" -ne 0 ]; then
	echo "Run this installer as root."
	exit 1
fi

if ! grep -q "LibreELEC\|OpenELEC" /etc/issue 2>/dev/null; then
	echo "This installer is intended for LibreELEC or OpenELEC."
	exit 1
fi

if [ "$#" -gt 1 ]; then
	echo "Usage: $0 [package-url]"
	exit 1
fi

if [ "$#" -eq 1 ]; then
	PACKAGE_URL="$1"
else
	PACKAGE_URL="$(
		curl -fsSL "https://api.github.com/repos/${REPOSITORY}/releases/tags/${RELEASE_TAG}" |
		sed -n 's/^[[:space:]]*"browser_download_url":[[:space:]]*"\([^"]*Linux-x86_64\.tar\.gz\)".*/\1/p' |
		head -n 1
	)"
fi

if [ -z "${PACKAGE_URL}" ]; then
	echo "Unable to find an x86_64 package in the ${RELEASE_TAG} release."
	echo "Run this script again with the package URL as its first argument."
	exit 1
fi

CACHE_DIRECTORY="/storage/.cache"
ARCHIVE_PATH="${CACHE_DIRECTORY}/hyperion-x86_64-${RELEASE_TAG}.tar.gz"
BACKUP_DIRECTORY="${TARGET_DIRECTORY}.backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "${CACHE_DIRECTORY}"

echo "Downloading ${PACKAGE_URL}"
curl -fL --retry 3 -o "${ARCHIVE_PATH}" "${PACKAGE_URL}"

if ! tar -tzf "${ARCHIVE_PATH}" | grep -q '^share/hyperion/bin/hyperiond$'; then
	echo "The downloaded archive is not a Hyperion x86_64 package."
	exit 1
fi

if [ -d "${TARGET_DIRECTORY}" ]; then
	echo "Stopping ${SERVICE_NAME}"
	systemctl stop "${SERVICE_NAME}"

	echo "Backing up ${TARGET_DIRECTORY} to ${BACKUP_DIRECTORY}"
	cp -a "${TARGET_DIRECTORY}" "${BACKUP_DIRECTORY}"
fi

echo "Installing Hyperion"
tar --strip-components=1 -xzf "${ARCHIVE_PATH}" -C /storage share/hyperion
chmod +x "${TARGET_DIRECTORY}/bin/hyperiond"

echo "Starting ${SERVICE_NAME}"
systemctl start "${SERVICE_NAME}"

sleep 2
if curl -fsS -D - -o /dev/null http://127.0.0.1:8090/ | grep -qi '^Content-Type: text/html'; then
	echo "Hyperion Web UI is serving HTML correctly."
	echo "Open http://$(hostname -I | awk '{print $1}'):8090/"
else
	echo "Hyperion started, but the Web UI MIME-type check failed."
	echo "Your previous installation is backed up at ${BACKUP_DIRECTORY}."
	exit 1
fi
