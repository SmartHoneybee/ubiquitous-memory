#!/bin/sh
set -ex
echo '@edge http://nl.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories
apk --update-cache --no-progress add git gcc g++ make wget go nodejs nodejs-npm libjpeg-turbo-utils pngquant@edge gifsicle optipng yarn
mkdir ~/go
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
ulimit -n 8096
mkdir -p ~/go/src/github.com/mattermost
cd ~/go/src/github.com/mattermost
V=4.3.0
wget "https://github.com/mattermost/mattermost-server/archive/v${V}.tar.gz"
tar xf "v${V}.tar.gz"
mv "mattermost-server-${V}" mattermost-server
rm "v${V}.tar.gz"
wget "https://github.com/mattermost/mattermost-webapp/archive/v${V}.tar.gz"
tar xf "v${V}.tar.gz"
mv "mattermost-webapp-${V}" mattermost-webapp
rm "v${V}.tar.gz"
cd ~/go/src/github.com/mattermost/mattermost-webapp
make build -i # ignore errors
cd ~/go/src/github.com/mattermost/mattermost-server
patch -p1 < /build/make.patch
make build-linux package
cp -rv ~/go/src/github.com/mattermost/mattermost-server/dist/* /build/
