# Thin extension of the official image. We do NOT build Keycloak from source.
# Bump this tag to take upstream security patches.
ARG KC_VERSION=26.0

FROM quay.io/keycloak/keycloak:${KC_VERSION} AS builder

# Build-time options get baked into the image so runtime can use --optimized.
ENV KC_DB=postgres \
    KC_HEALTH_ENABLED=true \
    KC_METRICS_ENABLED=true \
    KC_HTTP_RELATIVE_PATH=/auth

# Drop custom SPI jars in providers/ and login themes in themes/ and they get
# picked up by kc.sh build. Both are optional; neither exists yet.
COPY --chown=keycloak:root providers/ /opt/keycloak/providers/
COPY --chown=keycloak:root themes/    /opt/keycloak/themes/

RUN /opt/keycloak/bin/kc.sh build


FROM quay.io/keycloak/keycloak:${KC_VERSION}
COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Realm definition, no users. Users are created per environment.
COPY --chown=keycloak:root realm/notes-realm.json /opt/keycloak/data/import/

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--optimized"]
