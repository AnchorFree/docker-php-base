# =========================================== #
# FIRST STEP - BUILDING PHP EXTENSIONS        #
# =========================================== #

FROM php:7.1-fpm-alpine AS build-env

# PREPARE
RUN docker-php-source extract

# CONFIGURE APK
# https://wiki.alpinelinux.org/wiki/Alpine_Linux_package_management#Repository_pinning
RUN echo '@edge-main http://dl-cdn.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories
RUN echo '@edge-community http://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories
RUN echo '@edge-testing http://dl-cdn.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories
RUN apk update
RUN apk add --upgrade apk-tools@edge-main

RUN apk add \
    coreutils \
    postgresql-dev@edge-main \
    libmcrypt-dev \
    bzip2-dev \
    libpng-dev \
    libxslt-dev \
    gettext-dev \
    autoconf \
    g++ \
    make \
    cmake \
    geoip-dev \
    libmemcached-dev \
    cyrus-sasl-dev \
    pcre-dev \
    git \
    file \
    freetype-dev \
    libjpeg-turbo-dev \
    re2c \
    libressl-dev@edge-main \
    rabbitmq-c-dev@edge-main

# =================== #
# PHP CORE EXTENSIONS #
# =================== #

RUN docker-php-ext-configure \
    gd --with-freetype-dir=/usr/lib --with-jpeg-dir=/usr/lib --with-png-dir=/usr/lib

RUN docker-php-ext-install -j$(getconf _NPROCESSORS_ONLN) \
    mcrypt \
    mysqli \
    bz2 \
    opcache \
    calendar \
    gd \
    pcntl \
    xsl \
    soap \
    shmop \
    sysvmsg \
    sysvsem \
    sysvshm \
    sockets \
    pdo_mysql \
    pdo_pgsql \
    pgsql \
    wddx

RUN docker-php-ext-enable opcache

# =============== #
# PECL EXTENSIONS #
# =============== #

RUN pecl channel-update pecl.php.net

RUN pecl install \
    amqp \
    apcu \
    geoip-beta \
    msgpack \
    xdebug \
    igbinary

RUN docker-php-ext-enable \
    amqp \
    apcu \
    geoip \
    msgpack \
    igbinary

# ================= #
# CUSTOM EXTENSIONS #
# ================= #

RUN git clone --branch php7 --single-branch --depth 1 https://github.com/php-memcached-dev/php-memcached
RUN cd php-memcached && phpize && ./configure --enable-memcached-igbinary && make -j$(getconf _NPROCESSORS_ONLN) && make install

# blitz
RUN git clone --branch php7 --single-branch --depth 1 https://github.com/alexeyrybak/blitz.git blitz
RUN cd blitz && phpize && ./configure && make -j$(getconf _NPROCESSORS_ONLN) && make install

# handlersocketi
RUN git clone --branch badoo-7.0 --single-branch --depth 1 https://github.com/tony2001/php-ext-handlersocketi.git handlersocketi
RUN cd handlersocketi && phpize && ./configure  && make -j$(getconf _NPROCESSORS_ONLN)  && make install

# pinba
RUN git clone --branch master --single-branch --depth 1 https://github.com/tony2001/pinba_extension.git pinba
RUN cd pinba && phpize && ./configure && make -j$(getconf _NPROCESSORS_ONLN) && make install

# protobuf
RUN git clone --branch php7 --single-branch --depth 1 https://github.com/serggp/php-protobuf protobuf
RUN cd protobuf && phpize && ./configure && make -j$(getconf _NPROCESSORS_ONLN) && make install

RUN docker-php-ext-enable \
    blitz \
    handlersocketi \
    pinba \
    protobuf \
    memcached



# =========================================== #
# SECOND STEP - BUILDING PHP CONTAINER ITSELF #
# =========================================== #

FROM php:7.1-fpm-alpine

# CONFIGURE APK
# https://wiki.alpinelinux.org/wiki/Alpine_Linux_package_management#Repository_pinning
RUN echo '@edge-main http://dl-cdn.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories
RUN echo '@edge-community http://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories
RUN echo '@edge-testing http://dl-cdn.alpinelinux.org/alpine/edge/testing' >> /etc/apk/repositories
RUN apk update
RUN apk add --upgrade apk-tools@edge-main

LABEL maintainer "Aleksandr Ilin <ailyin@anchorfree.com>"

EXPOSE 9000 9001 9002

RUN rm -rfv /var/www/html && \
    apk add libmcrypt libbz2 libpng libxslt gettext openssl geoip libmemcached cyrus-sasl freetype libjpeg-turbo python postgresql rabbitmq-c@edge-main && \
    mkdir -v -m 755 /var/run/php-fpm && \
    chmod 777 /var/log

# php -d error_reporting=22527 -d display_errors=1 -r 'var_dump(iconv("UTF-8", "UTF-8//IGNORE", "This is the Euro symbol '\''€'\''."));'
# Notice: iconv(): Wrong charset, conversion from `UTF-8' to `UTF-8//IGNORE' is not allowed in Command line code on line 1
RUN apk add gnu-libiconv@edge-testing
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php

# INSTALL DEV RELATED SYSTEM TOOLS
RUN apk add bash grep git openssh-client rsync

COPY --from=build-env /usr/local/lib/php/extensions/* /usr/local/etc/php/extensions/
COPY --from=build-env /usr/local/etc/php/conf.d/* /artifacts/usr/local/etc/php/conf.d/
RUN find /usr/local/lib/php/extensions/ -name *.so | xargs -I@ sh -c 'ln -s @ /usr/local/lib/php/extensions/`basename @`'
RUN cp -r /artifacts/usr/local/etc/php/conf.d/* /usr/local/etc/php/conf.d/
RUN rm -rfv /usr/local/etc/php-fpm.d/*

RUN apk --update-cache add python py-requests gzip
