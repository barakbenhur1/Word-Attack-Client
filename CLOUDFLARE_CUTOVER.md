# WordZap Cloudflare client cutover

The client is prepared for a staged backend migration without changing the
current production endpoint before the Cloudflare backend passes acceptance.

## Backend selection

`Word Guess/Network/Network.swift` owns `BackendConfiguration`.

Default behavior remains the legacy Render URL. A staged or production build can
override it with the Info.plist key:

```
WORDZAP_API_BASE_URL
```

When the configured host ends in `.workers.dev`, PVP automatically uses the
native Cloudflare WebSocket transport at `/pvp/socket`. A custom domain can
explicitly enable it with:

```
WORDZAP_NATIVE_PVP = true
```

REST networking, PVP shared-word requests and device-token registration all use
the same backend configuration so a cutover cannot intentionally split those
paths across different origins.

## PVP transport

Render rollback mode keeps the existing Socket.IO implementation.

Cloudflare mode uses `NativePvPWebSocketClient` and preserves the existing
application-level events for queueing, match discovery, coin flip, typing,
turns, opponent leave and queue leave. Match-scoped word lookup is fail-closed
in Cloudflare mode: if `/pvp/word` fails, the client does not generate/fetch a
different per-player word.

## Production gate

Do not add `WORDZAP_API_BASE_URL` to the production Info.plist until all of
these are green:

1. Cloudflare D1 + Worker + Durable Object deployed.
2. Existing MongoDB production state imported and counts reconciled.
3. Live backend production smoke passes.
4. APNs Cloudflare secrets configured and a real-device token registers.
5. Two real iOS devices pass matchmaking, shared word, coin flip, typing, turn
   switching, opponent leave, reconnect and rematch.
6. iOS simulator build and the Cloudflare client cutover CI are green.

Render remains the rollback endpoint until that gate is complete.
