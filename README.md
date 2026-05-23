# mengbin92.github.io

This site is built with Gobin, not Jekyll.

## Local build

```bash
docker compose run --rm gobin-build build --minify
```

## Auto deploy

Pushes to `main` trigger `.github/workflows/deploy.yml`, which SSHes into the Tencent server,
pulls the latest commit, and restarts the local compose stack. The `gobin-build` service
keeps `public/` rebuilt automatically when source files change.
