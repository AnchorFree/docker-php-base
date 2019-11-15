# =========================================== #
# FIRST STEP - BUILDING PHP EXTENSIONS        #
# =========================================== #

FROM php:7.2.22-fpm-alpine3.10 AS build-env

# PREPARE
RUN docker-php-source extract

# UPDATE APK
RUN apk update
RUN apk add --upgrade apk-tools
RUN apk add \
    coreutils \
    postgresql-dev \
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
    libressl-dev \
    rabbitmq-c-dev

# =================== #
# PHP CORE EXTENSIONS #
# =================== #

RUN docker-php-ext-configure \
    gd --with-freetype-dir=/usr/lib --with-jpeg-dir=/usr/lib --with-png-dir=/usr/lib

RUN docker-php-ext-install -j$(getconf _NPROCESSORS_ONLN) \
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
    wddx \
    zip

RUN docker-php-ext-enable opcache

# =============== #
# PECL EXTENSIONS #
# =============== #

RUN pecl channel-update pecl.php.net

RUN pecl install \
    mcrypt \
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

# php-memcached
RUN git clone --branch php7 --single-branch https://github.com/php-memcached-dev/php-memcached php-memcached \
 && cd php-memcached \
 && git checkout e65be324557eda7167c4831b4bfb1ad23a152beb \
 && git reset --hard
RUN cd php-memcached \
 && phpize \
 && ./configure --enable-memcached-igbinary \
 && make -j$(getconf _NPROCESSORS_ONLN) \
 && make install

# blitz
RUN git clone --branch php7 --single-branch https://github.com/alexeyrybak/blitz.git blitz \
 && cd blitz \
 && git checkout 2353a6b0c35418415c76d3659456f40032e90690 \
 && git reset --hard
RUN cd blitz \
 && phpize \
 && ./configure \
 && make -j$(getconf _NPROCESSORS_ONLN) \
 && make install

# handlersocketi
RUN git clone --branch badoo-7.0 --single-branch https://github.com/tony2001/php-ext-handlersocketi.git handlersocketi \
 && cd handlersocketi \
 && git reset --hard 467fa24ec91c02435e059d60175d9ea20a985a5b
RUN cd handlersocketi \
 && phpize \
 && ./configure \
 && make -j$(getconf _NPROCESSORS_ONLN) \
 && make install

# pinba
RUN git clone --branch master --single-branch https://github.com/tony2001/pinba_extension.git pinba \
 && cd pinba \
 && git reset --hard edbc313f1b4fb8407bf7d5acf63fbb0359c7fb2e
RUN cd pinba \
 && phpize \
 && ./configure \
 && make -j$(getconf _NPROCESSORS_ONLN) \
 && make install

# protobuf
RUN git clone --branch php7 --single-branch --depth 1 https://github.com/serggp/php-protobuf protobuf \
 && cd protobuf \
 && git reset --hard c969785f89ada150941f9ddce20dacf4b95d0f7f
RUN cd protobuf \
 && phpize \
 && ./configure \
 && make -j$(getconf _NPROCESSORS_ONLN) \
 && make install

# enable custom extentions
RUN docker-php-ext-enable \
    blitz \
    handlersocketi \
    pinba \
    protobuf \
    memcached

# =========================================== #
# SECOND STEP - BUILDING PHP CONTAINER ITSELF #
# =========================================== #

FROM php:7.2.22-fpm-alpine3.10

# UPDATE APK
RUN apk update
RUN apk add --upgrade apk-tools

LABEL maintainer "Aleksandr Ilin <ailyin@anchorfree.com>"

EXPOSE 9000 9001 9002

RUN rm -rfv /var/www/html \
 && apk add \
      libmcrypt \
      libbz2 \
      libpng \
      libxslt \
      gettext \
      openssl \
      geoip \
      libmemcached \
      cyrus-sasl \
      freetype \
      libjpeg-turbo \
      python \
      postgresql \
      rabbitmq-c \
 && mkdir -v -m 755 /var/run/php-fpm \
 && chmod 777 /var/log

# php -d error_reporting=22527 -d display_errors=1 -r 'var_dump(iconv("UTF-8", "UTF-8//IGNORE", "This is the Euro symbol '\''€'\''."));'
# Notice: iconv(): Wrong charset, conversion from `UTF-8' to `UTF-8//IGNORE' is not allowed in Command line code on line 1
RUN apk add gnu-libiconv
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php

# INSTALL DEV RELATED SYSTEM TOOLS
RUN apk add bash grep git openssh-client rsync

COPY --from=build-env /usr/local/lib/php/extensions/* /usr/local/etc/php/extensions/
COPY --from=build-env /usr/local/etc/php/conf.d/* /artifacts/usr/local/etc/php/conf.d/
RUN find /usr/local/lib/php/extensions/ -name *.so | xargs -I@ sh -c 'ln -s @ /usr/local/lib/php/extensions/`basename @`'
RUN cp -r /artifacts/usr/local/etc/php/conf.d/* /usr/local/etc/php/conf.d/
RUN rm -rfv /usr/local/etc/php-fpm.d/*

RUN apk --update-cache add python py-requests gzip
