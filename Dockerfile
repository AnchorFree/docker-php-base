# =========================================== #
# FIRST STEP - BUILDING PHP EXTENSIONS        #
# =========================================== #

FROM php:7.4.15-fpm-alpine3.13 AS build-env

# PREPARE
RUN docker-php-source extract

# CONFIGURE APK
# https://wiki.alpinelinux.org/wiki/Alpine_Linux_package_management#Repository_pinning
RUN apk update \
 && apk upgrade \
 && apk add --upgrade apk-tools

RUN apk add \
    autoconf \
    bzip2-dev \
    libzip-dev \
    cmake \
    coreutils \
    cyrus-sasl-dev \
    file \
    freetype-dev \
    g++ \
    geoip-dev \
    gettext-dev \
    git \
    libjpeg-turbo-dev \
    libmcrypt-dev \
    libmemcached-dev \
    libpng-dev \
    libressl-dev \
    libxslt-dev \
    make \
    pcre-dev \
    postgresql-dev \
    rabbitmq-c-dev \
    re2c

# =================== #
# PHP CORE EXTENSIONS #
# =================== #

# https://github.com/docker-library/php/issues/912#issuecomment-559918036
RUN docker-php-ext-configure \
    gd --with-freetype=/usr/lib --with-jpeg=/usr/lib

RUN docker-php-ext-install -j$(getconf _NPROCESSORS_ONLN) \
    bz2 \
    calendar \
    gd \
    mysqli \
    opcache \
    pcntl \
    pdo_mysql \
    pdo_pgsql \
    pgsql \
    shmop \
    soap \
    sockets \
    sysvmsg \
    sysvsem \
    sysvshm \
    xsl \
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
    memcached \
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
    memcached \
    pinba \
    protobuf

# =========================================== #
# SECOND STEP - BUILDING PHP CONTAINER ITSELF #
# =========================================== #

FROM php:7.4.15-fpm-alpine3.13

# CONFIGURE APK
# https://wiki.alpinelinux.org/wiki/Alpine_Linux_package_management#Repository_pinning
RUN echo '@edge-community http://dl-cdn.alpinelinux.org/alpine/edge/community' >> /etc/apk/repositories
RUN apk update \
 && apk upgrade \
 && apk add --upgrade apk-tools

LABEL maintainer="Aleksandr Ilin <ailyin@anchorfree.com>"

EXPOSE 9000 9001 9002

RUN rm -rfv /var/www/html \
 && apk --update-cache add \
      cyrus-sasl \
      freetype \
      geoip \
      gettext \
      libbz2 \
      libjpeg-turbo \
      libmcrypt \
      libmemcached \
      libpng \
      libxslt \
      openssl \
      postgresql \
      python2 \
      py-requests \
      gzip \
      rabbitmq-c \
 && mkdir -v -m 755 /var/run/php-fpm \
 && chmod 777 /var/log

# php -d error_reporting=22527 -d display_errors=1 -r 'var_dump(iconv("UTF-8", "UTF-8//IGNORE", "This is the Euro symbol '\''€'\''."));'
# Notice: iconv(): Wrong charset, conversion from `UTF-8' to `UTF-8//IGNORE' is not allowed in Command line code on line 1
RUN apk add gnu-libiconv@edge-community
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php

# INSTALL DEV RELATED SYSTEM TOOLS
RUN apk add \
      bash \
      grep \
      git \
      openssh-client \
      rsync

COPY --from=build-env /usr/local/lib/php/extensions/* /usr/local/etc/php/extensions/
COPY --from=build-env /usr/local/etc/php/conf.d/* /artifacts/usr/local/etc/php/conf.d/
RUN find /usr/local/lib/php/extensions/ -name *.so | xargs -I@ sh -c 'ln -s @ /usr/local/lib/php/extensions/`basename @`'
RUN cp -r /artifacts/usr/local/etc/php/conf.d/* /usr/local/etc/php/conf.d/
RUN rm -rfv /usr/local/etc/php-fpm.d/*

RUN sed -e 's/countryName_default/#countryName_default/' -e 's/stateOrProvinceName_default/#stateOrProvinceName_default/' \
    -e 's/0.organizationName_default/#0.organizationName_default/' -i /etc/ssl/openssl.cnf
