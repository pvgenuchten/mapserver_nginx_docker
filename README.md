# Mapserver NGINX Docker

A Debian+NGINX based docker image for mapserver via fastcgi.
Prepared for using a mapfile alias in mapserver config file.

## Features

- Call your maps as http://{server}/{alias}?service=wms&request=getcapabilities
- Includes microsoft core fonts, reference fontset at '/etc/mapserver/fonts.txt'
- Includes a robots.txt and favicon.ico
- The default image includes a default map, called countries
- Mapserver index page and OGCAPI pre configured on the default map
- CORS headers enabled

## Build

```
# from within the mapserver_nginx_docker folder
docker build -t pvgenuchten/mapserver_nginx_docker .

# with different build parameters
docker build --build-arg MAPSERVER_REF=main -t pvgenuchten/mapserver_nginx_docker:main .

```

## Run

```
# local built version
docker run --rm -p 8080:80 pvgenuchten/mapserver_nginx_docker

# MapServer main build
docker run --rm -p 8080:80 pvgenuchten/mapserver_nginx_docker:main

# or for the prebuilt version
docker run -p 8080:80 ghcr.io/pvgenuchten/mapserver_nginx_docker
```

Navigate to <http://localhost:8080>

## Config

- Mount the data folder to /maps.
- Add a mapserver.conf to the data folder, with an alias for each mapfile. If there is no mapserver.conf, the built-in default config is used.
- The public base URL used in GetCapabilities / OGC API links defaults to `http://localhost:8080/`. Set it at runtime with `-e MS_ONLINERESOURCE=...`
  at startup it replaces `@MS_ONLINERESOURCE@` in the config file (your file is not modified).

```
docker run --rm -p 8080:80 \
  -e MS_ONLINERESOURCE=https://maps.example.org/ \
  -v $(pwd)/maps:/maps:ro \
  pvgenuchten/mapserver_nginx_docker
```

Example maps/mapserver.conf:

```
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
```

## Test

Use [wms-tester](https://github.com/pvgenuchten/wms-tester) to test your image
