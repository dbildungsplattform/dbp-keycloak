FROM debian:13-slim AS base

# prepare base, as both build and final layer need java
RUN apt-get update && \
  apt-get install -y --no-install-recommends openjdk-21-jre-headless && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

FROM base AS build

ARG KEYCLOAK_VARIANT="generic"

# load env vars for base and the selected variant
COPY ./variants/base/env /tmp/env-base
COPY ./variants/${KEYCLOAK_VARIANT}/env /tmp/env-variant

# Download und Import des Keycloak-PGP-Schlüssels
RUN apt-get update && apt-get install -y --no-install-recommends curl gnupg unzip tar && \
    gpg --import keycloak-2.asc

RUN set -o allexport && \
    . /tmp/env-base && \
    . /tmp/env-variant && \
    set +a && \
    env && \
    echo "Building variant ${KEYCLOAK_VARIANT} with keycloak version ${KEYCLOAK_VERSION}" && \
    mkdir "/tmp/keycloak" && \
    cd /tmp/keycloak && \
    export ARCHIVE=keycloak-${KEYCLOAK_VERSION}.tar.gz; \
    curl -fLO https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/${ARCHIVE}; \
    curl -fLO https://github.com/keycloak/keycloak/releases/download/${KEYCLOAK_VERSION}/${ARCHIVE}.asc; \
    gpg --verify ${ARCHIVE}.asc ${ARCHIVE}; \
    tar -xvf ${ARCHIVE}; \
    rm ${ARCHIVE}*; \
    mv keycloak-* /opt/keycloak && \
    mkdir -p /opt/keycloak/data && \
    mkdir -p /opt/keycloak/themes && \
    mkdir -p /opt/keycloak/providers && \
    chmod -R g+rwX /opt/keycloak

# load files for base and the selected variant
COPY ./variants/base/files/ /opt/keycloak/
COPY ./variants/${KEYCLOAK_VARIANT}/files/ /opt/keycloak/

# remove unused .gitkeep files
RUN rm -f /opt/keycloak/.gitkeep

# generate ssl cert for dev
WORKDIR /opt/keycloak/
RUN keytool -genkeypair -storepass password -storetype PKCS12 -keyalg RSA -keysize 2048 -dname "CN=keycloak" -alias keycloak -ext "SAN:c=DNS:localhost,IP:127.0.0.1" -validity 365 -keystore conf/server.keystore

# execute build
# ignore hadolint file not found error
# hadolint ignore=SC1091
RUN set -o allexport && \
    . /tmp/env-base && \
    . /tmp/env-variant && \
    set +a && \
    /opt/keycloak/bin/kc.sh build && \
    /opt/keycloak/bin/kc.sh show-config

RUN echo "Built variant $KEYCLOAK_VARIANT"

# build final image
FROM base AS final

COPY --from=build --chown=65532:65532 /opt/ /opt/
WORKDIR /opt/keycloak
USER 65532
ENTRYPOINT [ "/opt/keycloak/bin/kc.sh", "start" , "--optimized" ]
