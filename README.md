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
  because anything shipped to a browser is public. Redirect URIs are exact,
  port included: Keycloak matches the port, so reaching the app through a
  port-forward needs that port listed. `:8081` is present for exactly that.
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

## Realm import gotchas, all learned the hard way

Keycloak's realm import is quietly partial. Four things in this file look
optional and are not:

1. **Do not hand-list `defaultClientScopes`.** Omitting Keycloak's `basic`
   scope removes the `sub` claim from every access token, and the API cannot
   identify the caller. The field is absent here so the realm defaults apply.
2. **Composites must be declared where they resolve.** A top-level
   `defaultRole` block with a `composites` list is ignored: Keycloak builds its
   own `default-roles-notes` and drops your entries, so the default role never
   gets granted. Declaring the composite inside `roles.realm` is what sticks.
3. **Every role named in a composite must be declared too.** Declaring
   `roles.realm` replaces the implicit list, and referencing an undeclared role
   fails the whole import with `Unable to find composite realm role`.
4. **`fullScopeAllowed: false` needs `scopeMappings`.** Without them no realm
   role reaches the token. That combination is deliberate: the token carries
   only the two roles this app uses, not every role the user happens to hold.

## Endpoints

Everything Keycloak is under `/auth` (`KC_HTTP_RELATIVE_PATH`), which keeps the
ingress to three clean prefixes: `/`, `/api`, `/auth`.

- issuer: `<public-url>/auth/realms/notes`
- JWKS: `<url>/auth/realms/notes/protocol/openid-connect/certs`
- health: port **9000**, `/auth/health/ready`. The management interface has
  its own port but not its own path: `http-management-relative-path` defaults
  to `http-relative-path`, so health sits under `/auth` too. Probing
  `/health/ready` returns 404, and a liveness probe pointed there will kill a
  Keycloak that started fine.

`KC_HOSTNAME` must include the `/auth` path. It sets the entire public base URL,
so without the path Keycloak serves at `/auth` but advertises an issuer without
it, and every token gets rejected downstream.

Keycloak sets its auth cookies `Secure; SameSite=None`. Browsers only accept
`Secure` cookies from a trustworthy origin, so a plain-HTTP deployment has to be
on `localhost` or `*.localhost`. A loopback-resolving domain like
`*.localtest.me` is not trustworthy to the browser and produces a login that
loops with no error anywhere.
