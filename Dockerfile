# =========================================== #
# FIRST STEP - BUILDING PHP EXTENSIONS        #
# =========================================== #

FROM php:7.1-fpm-alpine
FROM anchorfree/elite-sources:master AS source-code
FROM php:7.1-fpm-alpine AS build-env

# PREPARE
RUN docker-php-source extract

RUN apk add --no-cache \
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
    re2c

RUN apk add --no-cache --repository http://dl-3.alpinelinux.org/alpine/edge/main \
    libressl-dev \
    rabbitmq-c-dev

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

LABEL maintainer "Aleksandr Ilin <ailyin@anchorfree.com>"

EXPOSE 9000 9001 9002

WORKDIR /srv/app/hsselite/live

RUN rm -rfv /var/www/html && \
    apk add --no-cache libmcrypt libbz2 libpng libxslt gettext openssl geoip libmemcached cyrus-sasl freetype libjpeg-turbo python postgresql && \
    apk add rabbitmq-c --no-cache --repository http://dl-3.alpinelinux.org/alpine/edge/main && \
    addgroup -g 5555 srv && adduser -G srv -u 5555 -D -h /srv srv && \
    mkdir -v -m 755 /var/run/php-fpm && chown -c srv:srv /var/run/php-fpm && \
    chown -c srv:srv /srv && \
    chmod 777 /var/log

# php -d error_reporting=22527 -d display_errors=1 -r 'var_dump(iconv("UTF-8", "UTF-8//IGNORE", "This is the Euro symbol '\''€'\''."));'
# Notice: iconv(): Wrong charset, conversion from `UTF-8' to `UTF-8//IGNORE' is not allowed in Command line code on line 1
RUN apk add --no-cache --repository http://dl-3.alpinelinux.org/alpine/edge/testing gnu-libiconv
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php

# INSTALL DEV RELATED SYSTEM TOOLS
RUN apk add --no-cache bash grep git openssh-client rsync

ENV HSSELITE_ERROR_LOG /srv/log/php/php_errors.json
ENV POOLS_CONFIGURATION=/usr/local/etc/php-fpm.d/backend.conf
ENV PHP_ERROR_LOG_LOCATION  /var/log/php-error.log
ENV FPM_ERROR_LOG_LOCATION /var/log/fpm-error.log
ENV FPM_ERROR_LOG_LEVEL error
ENV FPM_SLOW_LOG_LOCATION /var/log/slow.log
ENV FPM_ACCESS_LOG_LOCATION /var/log/app-access.json
ENV PHP_INI_MEMORY_LIMIT 128M

ENV FPM_ANDROID_PM_MAX_CHILDREN 120
ENV FPM_ANDROID_PM_MAX_REQUESTS 300
ENV FPM_IOS_PM_MAX_CHILDREN 350
ENV FPM_IOS_PM_MAX_REQUESTS 1000
ENV FPM_WWW_PM_MAX_CHILDREN 240
ENV FPM_WWW_PM_MAX_REQUESTS 300
ENV FPM_AUTHORIZER_PM_MAX_CHILDREN 100
ENV FPM_AUTHORIZER_PM_MAX_REQUESTS 300

COPY --from=build-env /usr/local/lib/php/extensions/* /usr/local/etc/php/extensions/
COPY --from=build-env /usr/local/etc/php/conf.d/* /artifacts/usr/local/etc/php/conf.d/
RUN find /usr/local/lib/php/extensions/ -name *.so | xargs -I@ sh -c 'ln -s @ /usr/local/lib/php/extensions/`basename @`'
RUN cp -r /artifacts/usr/local/etc/php/conf.d/* /usr/local/etc/php/conf.d/

COPY --from=source-code /tmp/artifacts/build/ /srv/app/hsselite/live/
RUN chown -R srv:srv  /srv/app/hsselite/live/
RUN rm -rfv /usr/local/etc/php-fpm.d/*

RUN apk --update-cache add python py-requests gzip

ADD root /
