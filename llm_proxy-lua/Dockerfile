FROM alpine:3.22

LABEL maintainer="haller33 <anyone@anyone.com"

ENV LUA_VERSION=5.1.5

RUN set -ex \
    \
    && apk -U upgrade \
    && apk add --no-cache \
        readline \
    \
    && apk add --no-cache --virtual .build-deps \
        ca-certificates \
        openssl \
        make \
        gcc \
        libc-dev \
        readline-dev \
        ncurses-dev \
    \
    && wget --no-check-certificate -c \
        https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz \
        -O lua.tar.gz \
    && echo "b3882111ad02ecc6b972f8c1241647905cb2e3fc  lua.tar.gz" | \
        sha1sum -c -s - \
    && tar xzf lua.tar.gz \
    \
    && cd lua-${LUA_VERSION} \
    && make -j"$(nproc)" linux \
    && make install \
    && cd .. \
    && rm -rf lua.tar.gz lua-${LUA_VERSION} \
    \
    && apk del .build-deps

ENV LUAROCKS_VERSION=3.12.2

RUN set -ex \
    \
    && apk add --no-cache \
        ca-certificates \
        openssl \
        wget \
    \
    && apk add --no-cache --virtual .build-deps \
        make \
        gcc \
        libc-dev \
    \
    && wget https://luarocks.github.io/luarocks/releases/luarocks-${LUAROCKS_VERSION}.tar.gz \
        -O - | tar -xzf - \
    \
    && cd luarocks-${LUAROCKS_VERSION} \
    && ./configure --with-lua=/usr/local \
    && make build \
    && make install \
    && cd .. \
    && rm -rf luarocks-${LUAROCKS_VERSION} \
    \
    && apk del .build-deps


# Install system dependencies for build-time and run-time
# (OpenSSL is required for http.server, development headers for cjson)
RUN apk add --no-cache \
    gcc \
    m4 \
    musl-dev \
    make \
    openssl-dev \
    git \
    bsd-compat-headers \
    libgcc

RUN apk add --no-cache pcre2-dev

RUN luarocks install cqueues \
    && luarocks install luaossl \
    && luarocks install mime \
    && luarocks install luabitop

# Install the required Lua modules via LuaRocks
RUN luarocks install http
RUN luarocks install lua-cjson
# RUN luarocks install pcre2
# RUN luarocks install mime
RUN luarocks install pgmoon


# Set the working directory
WORKDIR /app

# Copy your Lua script into the container
COPY proxy.lua .

# Expose the port your server listens on
EXPOSE 5000

# Run the application
CMD ["lua", "proxy.lua"]
