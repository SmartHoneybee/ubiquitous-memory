#!/bin/sh
set -eux
# build user
BUILD_USER_HOME="${BUILD_USER_HOME:-/build}"
BUILD_USER_NAME="${BUILD_USER_NAME:-build}"
# Debian release used during build
DEBIAN_RELEASE="${DEBIAN_RELEASE:-stretch}"
# Mattermost version to build
MATTERMOST_RELEASE="${MATTERMOST_RELEASE:-v5.4.0}"
# node key id and release
NODE_KEY="${NODE_KEY:-9FD3B784BC1C6FC31A8A0A1C1655A0AB68576280}"
NODE_RELEASE="${NODE_RELEASE:-10}"
# golang version
GO_VERSION="${GO_VERSION:-1.15.5}"

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
		gnupg2 dirmngr apt-transport-https ca-certificates parallel
	# receive missing key (retry on failure)
	parallel --verbose --delay=30 --retries=5 "apt-key adv --keyserver 'ipv4.pool.sks-keyservers.net' --recv-keys '{}'" ::: "${NODE_KEY}"
	# add required additional repositories
	printf 'deb-src http://deb.debian.org/debian %s main' "${DEBIAN_RELEASE}" \
		> "/etc/apt/sources.list.d/${DEBIAN_RELEASE}-source.list"
	printf 'deb http://deb.debian.org/debian %s-backports main' "${DEBIAN_RELEASE}" \
		> "/etc/apt/sources.list.d/${DEBIAN_RELEASE}-backports.list"
	printf 'deb https://deb.nodesource.com/node_%s.x %s main' "${NODE_RELEASE}" "${DEBIAN_RELEASE}" \
		> '/etc/apt/sources.list.d/nodesource.list'
	# update repositories
	apt-get update
	# install dependencies
	apt-get install --quiet \
		wget build-essential patch git nodejs
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
	# switch to build user
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
# download and extract Mattermost sources
for COMPONENT in server webapp; do
	install --directory "${HOME}/go/src/github.com/mattermost/mattermost-${COMPONENT}"
	wget --quiet --continue --output-document="mattermost-${COMPONENT}.tar.gz" \
		"https://github.com/mattermost/mattermost-${COMPONENT}/archive/${MATTERMOST_RELEASE}.tar.gz"
	tar --directory="${HOME}/go/src/github.com/mattermost/mattermost-${COMPONENT}" \
		--strip-components=1 --extract --file="mattermost-${COMPONENT}.tar.gz"
done
# build Mattermost webapp
npm set progress false
sed -i -e 's#--verbose#--display minimal#' \
	"${HOME}/go/src/github.com/mattermost/mattermost-webapp/package.json"
make --directory="${HOME}/go/src/github.com/mattermost/mattermost-webapp" \
	build
# build Mattermost server
install --directory "${HOME}/go/bin"
if [ "$(go env GOOS)_$(go env GOARCH)" != 'linux_amd64' ]; then
	ln --symbolic \
		"${HOME}/go/bin/$(go env GOOS)_$(go env GOARCH)" \
		"${HOME}/go/bin/linux_amd64"
fi
patch --directory="${HOME}/go/src/github.com/mattermost/mattermost-server" \
	--strip=1 -t < "${HOME}/build-release.patch"
sed -i \
	-e 's#go generate#env --unset=GOOS --unset=GOARCH go generate#' \
	-e 's#$(GO) generate#env --unset=GOOS --unset=GOARCH go generate#' \
	-e 's#PWD#CURDIR#' \
	"${HOME}/go/src/github.com/mattermost/mattermost-server/Makefile" \
	"${HOME}/go/src/github.com/mattermost/mattermost-server/build/release.mk"
make --directory="${HOME}/go/src/github.com/mattermost/mattermost-server" \
	config-reset build-linux package-linux \
	BUILD_NUMBER="dev-$(go env GOOS)-$(go env GOARCH)-${MATTERMOST_RELEASE}" \
	GO="GOARCH=$(go env GOARCH) GOOS=$(go env GOOS) $(command -v go)" \
	PLUGIN_PACKAGES=''
# rename archive and calculate its SHA512 sum
mv "${HOME}/go/src/github.com/mattermost/mattermost-server/dist/mattermost-team-linux-amd64.tar.gz" \
	"${HOME}/mattermost-${MATTERMOST_RELEASE}-$(go env GOOS)-$(go env GOARCH).tar.gz"
sha512sum "${HOME}/mattermost-${MATTERMOST_RELEASE}-$(go env GOOS)-$(go env GOARCH).tar.gz" | \
	tee "${HOME}/mattermost-${MATTERMOST_RELEASE}-$(go env GOOS)-$(go env GOARCH).tar.gz.sha512sum"
