#!/bin/bash
set -eux
# build user
BUILD_USER_HOME="${BUILD_USER_HOME:-/build}"
BUILD_USER_NAME="${BUILD_USER_NAME:-build}"
# Debian release used during build
DEBIAN_RELEASE="${DEBIAN_RELEASE:-stretch}"
# Mattermost version to build
MATTERMOST_RELEASE="${MATTERMOST_RELEASE:-v7.10.0}"
MMCTL_RELEASE="${MMCTL_RELEASE:-v7.10.0}"
# golang version
GO_VERSION="${GO_VERSION:-1.19}"

if [ "$(id -u)" -eq 0 ]; then # as root user
	# create build user, if needed
	set +e
	if ! id -u "${BUILD_USER_NAME}"; then # create build user
		set -e
		useradd --create-home --home-dir "${BUILD_USER_HOME}" --skel "${PWD}" \
			"${BUILD_USER_NAME}"
	fi
	set -e
	# configure apt
	printf 'APT::Install-Recommends "0";' \
		> '/etc/apt/apt.conf.d/99-no-install-recommends'
	printf 'APT::Install-Suggests "0";' \
		> '/etc/apt/apt.conf.d/99-no-install-suggests'
	printf 'APT::Get::Assume-Yes "true";' \
		> '/etc/apt/apt.conf.d/99-assume-yes'
	# update repositories
	apt-get update
	# dependencies to setup repositories
	apt-get install --quiet \
		gnupg2 dirmngr apt-transport-https ca-certificates curl
	# add required additional repositories
	printf 'deb-src http://deb.debian.org/debian %s main' "${DEBIAN_RELEASE}" \
		> "/etc/apt/sources.list.d/${DEBIAN_RELEASE}-source.list"
	printf 'deb http://deb.debian.org/debian %s-backports main' "${DEBIAN_RELEASE}" \
		> "/etc/apt/sources.list.d/${DEBIAN_RELEASE}-backports.list"
	# update repositories
	apt-get update
	# install dependencies
	apt-get install --quiet \
		wget build-essential patch git python2
	# install 'pngquant' build dependencies (required by node module)
	apt-get build-dep --quiet \
		pngquant
	# install go from golang.org
	wget https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz
	tar -xvf go${GO_VERSION}.linux-amd64.tar.gz
	mv go /usr/local
	export GOROOT=/usr/local/go
	export PATH=$GOROOT/bin:$PATH
	# FIXME go (executed by build user) writes to GOROOT
	install --directory --owner="${BUILD_USER_NAME}" \
		"$(go env GOROOT)/pkg/$(go env GOOS)_$(go env GOARCH)"
	# Re-invoke this build.sh script with the 'build' user
	runuser -u "${BUILD_USER_NAME}" -- "${0}"
	# salvage build artifacts
	cp --verbose \
		"${BUILD_USER_HOME}/mattermost-${MATTERMOST_RELEASE}-$(go env GOOS)-$(go env GOARCH).tar.gz" \
		"${BUILD_USER_HOME}/mattermost-${MATTERMOST_RELEASE}-$(go env GOOS)-$(go env GOARCH).tar.gz.sha512sum" \
		"${HOME}"
	exit 0
fi
# as non-root user
export GOROOT=/usr/local/go
export PATH=$GOROOT/bin:$PATH
cd "${HOME}"

# install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

# download and extract Mattermost sources
for COMPONENT in server webapp; do
	install --directory "${HOME}/go/src/github.com/mattermost/mattermost-${COMPONENT}"
	wget --quiet --continue --output-document="mattermost-${COMPONENT}.tar.gz" \
		"https://github.com/mattermost/mattermost-${COMPONENT}/archive/${MATTERMOST_RELEASE}.tar.gz"
	tar --directory="${HOME}/go/src/github.com/mattermost/mattermost-${COMPONENT}" \
		--strip-components=1 --extract --file="mattermost-${COMPONENT}.tar.gz"
done

# install mattermost-webapp's required version of nodejs
pushd "${HOME}/go/src/github.com/mattermost/mattermost-webapp"
nvm install
popd

# prepare the go build environment
install --directory "${HOME}/go/bin"
if [ "$(go env GOOS)_$(go env GOARCH)" != 'linux_amd64' ]; then
	ln --symbolic \
		"${HOME}/go/bin/$(go env GOOS)_$(go env GOARCH)" \
		"${HOME}/go/bin/linux_amd64"
fi
# build mmctl
install --directory "${HOME}/go/src/github.com/mattermost/mmctl"
wget --quiet --continue --output-document="mmctl.tar.gz" \
	"https://github.com/mattermost/mmctl/archive/${MMCTL_RELEASE}.tar.gz"
tar --directory="${HOME}/go/src/github.com/mattermost/mmctl" \
	--strip-components=1 --extract --file="mmctl.tar.gz"
find "${HOME}/go/src/github.com/mattermost/mmctl/" -type f -name '*.go' | xargs \
	sed -i \
	-e 's#//go:build linux || darwin#//go:build linux || darwin || dragonfly || freebsd || netbsd || openbsd#' \
	-e 's#// +build linux darwin#// +build linux darwin dragonfly freebsd netbsd openbsd#'
make --directory="${HOME}/go/src/github.com/mattermost/mmctl" \
	BUILD_NUMBER="dev-$(go env GOOS)-$(go env GOARCH)-${MMCTL_RELEASE}" \
	ADVANCED_VET=0 \
	GO="GOARCH= GOOS= $(command -v go)"
# build Mattermost webapp
npm set progress false
sed -i -e 's#--verbose#--display minimal#' \
	"${HOME}/go/src/github.com/mattermost/mattermost-webapp/package.json"
make --directory="${HOME}/go/src/github.com/mattermost/mattermost-webapp" \
	build
# build Mattermost server
patch --directory="${HOME}/go/src/github.com/mattermost/mattermost-server" \
	--strip=1 -t < "${HOME}/build-release.patch"
sed -i \
	-e 's#go generate#env --unset=GOOS --unset=GOARCH go generate#' \
	-e 's#$(GO) generate#env --unset=GOOS --unset=GOARCH go generate#' \
	-e 's#PWD#CURDIR#' \
	"${HOME}/go/src/github.com/mattermost/mattermost-server/Makefile" \
	"${HOME}/go/src/github.com/mattermost/mattermost-server/build/release.mk"
make --directory="${HOME}/go/src/github.com/mattermost/mattermost-server" \
	config-reset \
	BUILD_NUMBER="dev-$(go env GOOS)-$(go env GOARCH)-${MATTERMOST_RELEASE}" \
	GO="GOARCH= GOOS= $(command -v go)" \
	PLUGIN_PACKAGES=''
make --directory="${HOME}/go/src/github.com/mattermost/mattermost-server" \
	build-linux package-linux \
	BUILD_NUMBER="dev-$(go env GOOS)-$(go env GOARCH)-${MATTERMOST_RELEASE}" \
	GO="GOARCH=$(go env GOARCH) GOOS=$(go env GOOS) $(command -v go)" \
	PLUGIN_PACKAGES=''
# rename archive and calculate its SHA512 sum
mv "${HOME}/go/src/github.com/mattermost/mattermost-server/dist/mattermost-team-linux-amd64.tar.gz" \
	"${HOME}/mattermost-${MATTERMOST_RELEASE}-$(go env GOOS)-$(go env GOARCH).tar.gz"
sha512sum "${HOME}/mattermost-${MATTERMOST_RELEASE}-$(go env GOOS)-$(go env GOARCH).tar.gz" | \
	tee "${HOME}/mattermost-${MATTERMOST_RELEASE}-$(go env GOOS)-$(go env GOARCH).tar.gz.sha512sum"
