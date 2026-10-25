# browser

A real, persistent [linuxserver/chromium](https://docs.linuxserver.io/images/docker-chromium/)
in Kubernetes, built for two consumers at once:

- **Automation** (agents, CLIs): a Chrome DevTools Protocol endpoint on
  port `9222` (`--remote-debugging-port` via the image's `CHROME_CLI`),
  reachable through the `cdp` service. Point tools that speak CDP at
  `http://<release>-cdp.<namespace>.svc.cluster.local:9222` — e.g. an agent's
  browser tools or `playwright.chromium.connect_over_cdp(...)`.

  Desktop chromium binds DevTools to `127.0.0.1` only and rejects non-IP
  `Host` headers, so the chart ships an `nginx` sidecar (`cdp-proxy`,
  port `9223` → `127.0.0.1:9222`) that fronts the endpoint: it rewrites the
  `Host` header, proxies WebSocket upgrades, and rewrites
  `webSocketDebuggerUrl` in `/json/*` responses back to the host the client
  asked for (clients such as playwright connect to that URL verbatim).
- **A human**: the Selkies web UI on port `3000` (the whole desktop streamed
  to a browser tab) for interactive logins, 2FA and captchas. Sessions done
  here persist in the profile volume, so automation reuses them.

The profile lives on a `ReadWriteOnce` PVC mounted at `/config`
(`--user-data-dir=/config/chrome-profile`), which survives pod restarts and
image upgrades. The chart guards `replicas: 1`: one profile, one writer.

## Values highlights

| Key | Default | Notes |
| --- | --- | --- |
| `controllers.main.containers.main.image.tag` | `latest` | Moving tag; `pullPolicy: Always`. Pin a digest to freeze. |
| `controllers.main.containers.main.env.CHROME_CLI` | CDP flags (see `values.yaml`) | Passed verbatim to the chromium binary. |
| `persistence.config.size` | `4Gi` | Profile, cookies, sessions. `retain: true`. |
| `service.main` | `3000/http` | Selkies web UI. |
| `service.cdp` | `9222/http` (targetPort `9223`) | CDP via the `cdp-proxy` sidecar. Cluster-internal only — **never** expose via ingress (CDP has no auth). |
| `ingress.main` | disabled | Web UI ingress. |

## Consumer example

```yaml
# values from the consuming Argo Application (site-specific bits live there)
ingress:
  main:
    enabled: true
    className: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.tls: "true"
      traefik.ingress.kubernetes.io/router.middlewares: <ns>-<middleware-name>@kubernetescrd
    hosts:
      - host: browser.example.org
        paths:
          - path: /
            pathType: Prefix
            service:
              identifier: main
              port: 3000
    tls:
      - hosts:
          - browser.example.org
controllers:
  main:
    containers:
      main:
        env:
          TZ: Etc/UTC # consumer's choice; the chart ships no TZ default
```

## Security notes

- The linuxserver image ships a **web terminal with passwordless sudo** on the
  web UI. Whoever reaches port 3000 owns the container: put an authenticating
  middleware (basic auth, forward auth) in front of the ingress, and keep
  port 3000/3001 out of any direct exposure.
- CDP (`9222`) is unauthenticated remote-code-execution-by-design. Keep it
  cluster-internal (the default service has no ingress).
