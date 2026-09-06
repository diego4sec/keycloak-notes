# keycloak-notes

The authentication artifact for the notes app.

## What this produces

A versioned OCI image: `ghcr.io/<owner>/keycloak-notes:<version>`.

That image tag is the **entire contract** with the `notes-app` repo. The app
repo pins it in `deploy/chart/values.yaml` under `keycloak.image`.

## Why this is not a clone of keycloak/keycloak

Building upstream Keycloak from source is a 20+ minute, multi-GB Maven build,
and it makes you responsible for their release cadence and CVE backports.
This repo extends the official image instead: bump `KC_VERSION` to take
upstream patches.

Clone the real repo only if you need to patch Keycloak internals.

## Layout

    Dockerfile                  FROM quay.io/keycloak/keycloak, runs kc.sh build
    realm/notes-realm.json      realm, clients, roles, audience mapper
    providers/                  custom SPI jars go here (empty)
    themes/                     custom login themes go here (empty)

## Build

    docker build -t keycloak-notes:dev .

Runtime is `start --optimized`, because `kc.sh build` already ran at image
build time. Never use `start-dev` outside a throwaway shell.

## What is in the realm

- realm `notes`, `sslRequired: external`, brute-force protection on
- `notes-web`: **public** client, PKCE S256, standard flow only. No secret,
  because anything shipped to a browser is public.
- `notes-api`: **bearer-only** client. It is the token audience, never a login.
- an audience mapper on `notes-web` so access tokens carry `aud: notes-api`.
  Without it the API rejects every token.
- realm roles `notes-user` (granted by default) and `notes-admin`.

## What is deliberately NOT in the realm

**No users.** A baked-in user with a known password is a credential shipped in
an image layer. Users are created per environment:

- local: the `kc-seed` one-shot service in `notes-app/docker-compose.yml`
- cloud: real identity, via federation or the admin console

## Realm changes

`--import-realm` only imports when the realm does not already exist, so
editing this file does **not** update a running realm. For local dev, drop the
Keycloak database. For cloud, `keycloak.importRealm` is `false` and the realm
is managed deliberately (terraform provider or a one-shot Job) so you never
end up with an untracked production realm.

## Endpoints

Everything Keycloak is under `/auth` (`KC_HTTP_RELATIVE_PATH`), which keeps the
ingress to three clean prefixes: `/`, `/api`, `/auth`.

- issuer: `<public-url>/auth/realms/notes`
- JWKS: `<url>/auth/realms/notes/protocol/openid-connect/certs`
- health: port **9000**, `/health/ready` (management port, not behind `/auth`)
