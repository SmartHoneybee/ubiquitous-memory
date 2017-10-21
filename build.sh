#!/bin/sh
set -ex
echo '@edge http://nl.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories
apk update
# dev guide
apk add gcc g++ make wget go nodejs
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
# hack
apk add libjpeg-turbo-utils
apk add pngquant@edge
apk add gifsicle
apk add optipng
# compiling
cd ~/go/src/github.com/mattermost/mattermost-server
make package
cp -rv ~/go/src/github.com/mattermost/mattermost-server/dist/* /build/
