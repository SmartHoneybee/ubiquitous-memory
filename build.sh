#!/bin/sh
set -ex
printf '@edge http://nl.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories
apk update
apk add libjpeg-turbo-utils
apk add pngquant@edge
apk add gifsicle
apk add optipng
