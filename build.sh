#!/bin/sh
set -ex
echo '@edge http://nl.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories
apk update
apk add libjpeg-turbo-utils
apk add pngquant@edge
apk add gifsicle
apk add optipng
