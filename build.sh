#!/bin/bash

set -e
set -x

# CLEAN FROM PREVIOUS BUILD
git clean -dfx .

# BUILD CLEAN IMAGES
docker build --pull --rm --file Dockerfile --tag anchorfree/php-elite .
