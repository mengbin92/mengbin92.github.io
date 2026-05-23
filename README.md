# mengbin92.github.io

This site is built with Gobin, not Jekyll.

## Local build

```bash
docker compose run --rm gobin-build build --minify
```

## Auto deploy

Pushes to `main` trigger `.github/workflows/deploy.yml`, which SSHes into the Tencent server,
pulls the latest commit, and restarts the local compose stack. Use a dedicated non-root
account on the server, for example `deploy`, and run Docker in rootless mode for that
account. That keeps the deploy key and SSH session away from `root`, while still letting
the site rebuild itself.

Suggested server-side setup:

1. Create a `deploy` user.
2. Install rootless Docker for that user.
3. Put this repo under that user's home directory, for example `/home/deploy/mengbin92.github.io`.
4. Set `TENCENT_DEPLOY_USER=deploy`, `TENCENT_SITE_DIR=/home/deploy/mengbin92.github.io`.
5. Keep `TENCENT_SSH_KEY` limited to that account only.
6. Keep `TENCENT_HOST` and `TENCENT_SSH_PORT` unchanged.

The `gobin-build` service keeps `public/` rebuilt automatically when source files change.
