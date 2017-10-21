#!/bin/sh
set -ex
apk update
apk add libjpeg-turbo-utils
apk add pngquant
apk add gifsicle
apk add optipng
