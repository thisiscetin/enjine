# Security Policy

Enjine is a library with no network access and no runtime dependencies. The
inputs that matter are card data, deck documents and game snapshots, which may
come from untrusted sources: they are parsed as JSON and validated before use.

## Supported versions

Only the latest release (and `main`) receives fixes while the project is pre-1.0.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's
[private vulnerability reporting](https://github.com/thisiscetin/enjine/security/advisories/new)
or email thisiscetin@gmail.com with a description and, if you can, a card, deck
or snapshot that reproduces it. You'll get a reply within a week.
