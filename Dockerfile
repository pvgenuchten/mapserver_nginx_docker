# syntax=docker/dockerfile:1.7

# ============================================================
# Stage 1: Build MapServer
# ============================================================
FROM debian:trixie-slim AS builder

# Any GitHub reference: a release tag (rel-8-6-6), a branch (main, branch-8-6)
ARG MAPSERVER_REF=rel-8-6-6

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    ca-certificates \
    curl \
    pkg-config \
    libfcgi-dev \
    libgdal-dev \
    libproj-dev \
    libgeos-dev \
    libxml2-dev \
    libcurl4-openssl-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype-dev \
    libtiff-dev \
    libpq-dev \
    libcairo2-dev \
    libfribidi-dev \
    libharfbuzz-dev \
    libgif-dev \
    libsqlite3-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN curl -fSL \
    "https://github.com/MapServer/MapServer/archive/${MAPSERVER_REF}.tar.gz" \
    -o mapserver.tar.gz \
    && mkdir mapserver \
    && tar -xzf mapserver.tar.gz \
        --strip-components=1 \
        -C mapserver \
    && rm mapserver.tar.gz

WORKDIR /build/mapserver/build

RUN cmake .. \
    -Wno-dev \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DWITH_FCGI=ON \
    -DWITH_CGI=ON \
    -DWITH_GDAL=ON \
    -DWITH_OGR=ON \
    -DWITH_PROJ=ON \
    -DWITH_GEOS=ON \
    -DWITH_POSTGIS=ON \
    -DWITH_MYSQL=OFF \
    -DWITH_WMS=ON \
    -DWITH_WFS=ON \
    -DWITH_PROTOBUFC=OFF \
    -DWITH_CAIRO=ON \
    -DWITH_FRIBIDI=ON \
    -DWITH_HARFBUZZ=ON \
    && cmake --build . --parallel 2 \
    && cmake --install .

# Verify FastCGI support and display version
RUN /usr/local/bin/mapserv -v \
    && /usr/local/bin/mapserv -v | grep -q "SUPPORTS=FASTCGI"

# ============================================================
# Stage 2: Minimal Nginx + MapServer
# ============================================================
FROM nginx:stable-trixie

ENV DEBIAN_FRONTEND=noninteractive
ENV PROJ_DATA=/usr/share/proj
ENV MS_ERRORFILE=stderr

ARG MSCOREFONTS_DEB=ttf-mscorefonts-installer_3.8.1_all.deb

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
    cabextract \
    xfonts-utils \
    fontconfig \
    wget \
    && echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" \
       | debconf-set-selections \
    && wget -q "https://deb.debian.org/debian/pool/contrib/m/msttcorefonts/${MSCOREFONTS_DEB}" \
    && apt-get install -y --no-install-recommends "./${MSCOREFONTS_DEB}" \
    && rm -f "${MSCOREFONTS_DEB}" \
    && fc-cache -f \
    && apt-get install -y --no-install-recommends \
    spawn-fcgi \
    tini \
    libfcgi0ldbl \
    libgdal36 \
    libproj25 \
    proj-data \
    gdal-data \
    libgeos-c1t64 \
    libxml2 \
    libcurl4t64 \
    libpq5 \
    libpng16-16t64 \
    libjpeg62-turbo \
    libtiff6 \
    libfreetype6 \
    libcairo2 \
    libfribidi0 \
    libharfbuzz0b \
    libgif7 \
    libpcre2-posix3 \
    libsqlite3-0 \
    zlib1g \
    fonts-dejavu-core \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# generate the mapserver fontlist
RUN mkdir -p /etc/mapserver && \
    find /usr/share/fonts -type f \( -iname "*.ttf" -o -iname "*.otf" \) \
    | while read font; do \
        name=$(basename "$font" | sed -E 's/\.(ttf|otf)$//' | tr '[:upper:]' '[:lower:]' | tr ' ' '-'); \
        echo "$name $font"; \
    done > /etc/mapserver/fonts.txt

# Copy compiled MapServer
COPY --from=builder /usr/local/ /usr/local/
COPY --from=builder \
    /build/mapserver/share/ogcapi/templates/html-index-bootstrap/ \
    /usr/local/share/mapserver/ogcapi/templates/html-index-bootstrap/
COPY --from=builder \
    /build/mapserver/share/ogcapi/templates/html-bootstrap/ \
    /usr/local/share/mapserver/ogcapi/templates/html-bootstrap/

RUN ldconfig \
    && ldd /usr/local/bin/mapserv \
    && ! ldd /usr/local/bin/mapserv | grep -q "not found"

RUN mkdir -p /maps \
    && chown nginx:nginx /maps \
    && chown nginx:nginx /usr/share/nginx/html

COPY maps/* /maps/.
COPY html/favicon.ico /usr/share/nginx/html/favicon.ico
COPY html/robots.txt /usr/share/nginx/html/robots.txt

# ============================================================
# Nginx configuration
# ============================================================
RUN rm -f /etc/nginx/conf.d/default.conf

RUN <<'EOF'
cat > /etc/nginx/conf.d/mapserver.conf <<'NGINX'
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
        
    # Serve robots.txt directly from /usr/share/nginx/html/robots.txt
    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    # Serve favicon.ico directly from /usr/share/nginx/html/favicon.ico
    location = /favicon.ico {
        allow all;
        log_not_found off;
        access_log off;
    }

    location / {
        # 1. Handle Anonymous CORS Preflight (OPTIONS)
        if ($request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' '*' always;
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }

        # 2. Inject CORS headers for actual requests (GET, POST)
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range' always;

        # Optional debug header to verify if cache is hit
        add_header X-Cache-Status $upstream_cache_status;
        include fastcgi_params;

        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME /usr/local/bin/mapserv;
        fastcgi_param SCRIPT_NAME "";
        fastcgi_param PATH_INFO $uri;

        fastcgi_connect_timeout 30s;
        fastcgi_send_timeout 120s;
        fastcgi_read_timeout 120s;

        fastcgi_buffering off;
    }
}
NGINX
EOF


ENV MS_ONLINERESOURCE=http://localhost:8080/

# Default config template. At startup /maps/mapserver.conf is used instead if it exists
# the chosen template is written to /etc/mapserver/mapserver.conf with
# @MS_ONLINERESOURCE@ replaced. The file in /maps is never modified.
RUN <<'EOF'
cat > /etc/mapserver/mapserver.conf.in <<'MAPCONF'
CONFIG
  ENV
    MS_MAP_NO_PATH "1"
    MS_ONLINERESOURCE "@MS_ONLINERESOURCE@"
    OGCAPI_HTML_TEMPLATE_DIRECTORY "/usr/local/share/mapserver/ogcapi/templates/html-bootstrap/"
    MS_INDEX_TEMPLATE_DIRECTORY "/usr/local/share/mapserver/ogcapi/templates/html-index-bootstrap/"
  END

  MAPS
    countries "/maps/countries.map"
  END
END
MAPCONF
EOF

ENV MAPSERVER_CONFIG_FILE=/etc/mapserver/mapserver.conf

# ============================================================
# FastCGI and Nginx startup
# No external entrypoint script required.
# Tini handles child process reaping.
# ============================================================

EXPOSE 80

ENTRYPOINT ["/usr/bin/tini", "--"]

CMD ["/bin/sh", "-ec", "if [ -f /maps/mapserver.conf ]; then tpl=/maps/mapserver.conf; else tpl=/etc/mapserver/mapserver.conf.in; fi; sed \"s|@MS_ONLINERESOURCE@|${MS_ONLINERESOURCE}|\" \"$tpl\" > \"$MAPSERVER_CONFIG_FILE\"; spawn-fcgi -a 127.0.0.1 -p 9000 -F 2 -u nginx -g nginx -f /usr/local/bin/mapserv; exec nginx -g 'daemon off;'"]

