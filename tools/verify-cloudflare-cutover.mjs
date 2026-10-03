import fs from "node:fs";

const files = {
  network: fs.readFileSync("Word Guess/Network/Network.swift", "utf8"),
  pvp: fs.readFileSync("Word Guess/Network/ViewModel/VsPlayerGameViewModel.swift", "utf8"),
  native: fs.readFileSync("Word Guess/Network/NativePvPWebSocketClient.swift", "utf8"),
  cutover: fs.readFileSync("tools/set-cloudflare-backend.mjs", "utf8")
};

function requireFragment(name, fragment) {
  if (!files[name].includes(fragment)) {
    throw new Error("Missing " + name + " fragment: " + fragment);
  }
}

requireFragment("network", "BackendConfiguration");
requireFragment("network", "WORDZAP_API_BASE_URL");
requireFragment("network", "WORDZAP_NATIVE_PVP");
requireFragment("network", "/pvp/socket");
requireFragment("network", "BackendConfiguration.apiBaseString");
requireFragment("pvp", "BackendConfiguration.apiBaseURL.appendingPathComponent(\"pvp/word\")");
requireFragment("pvp", "BackendConfiguration.usesNativePVP");
requireFragment("native", "pvp:queue:join");
requireFragment("native", "pvp:matchFound");
requireFragment("native", "pvp:coinflip");
requireFragment("native", "pvp:typing");
requireFragment("native", "pvp:rowDone");
requireFragment("native", "pvp:turn");
requireFragment("native", "pvp:opponentLeft");
requireFragment("native", "activeMatchPayload");
requireFragment("native", "scheduleReconnectLocked");
requireFragment("native", "pvp:reconnected");
requireFragment("native", "pvp:peerReconnecting");
requireFragment("cutover", '"/healthz"');
requireFragment("cutover", '"/ready"');
requireFragment("cutover", '"/ai/health"');
requireFragment("cutover", '"/push/health"');
requireFragment("cutover", "Cloudflare APNs readiness failed");
requireFragment("cutover", '"cloudflare-workers"');
requireFragment("cutover", '"durable-object-websocket"');
requireFragment("cutover", "refusing to modify production plist");

// The legacy host is intentionally allowed only in the central fallback config.
// This prevents a partial cutover where REST and PVP silently point at different backends.
for (const [name, body] of Object.entries(files)) {
  if (name === "network") {
    const occurrences = body.split("word-attack-server.onrender.com").length - 1;
    if (occurrences > 1) throw new Error("Legacy Render URL appears outside the central fallback in network");
    continue;
  }
  if (body.includes("word-attack-server.onrender.com")) {
    throw new Error("Legacy Render URL is still hard-coded in " + name);
  }
}

console.log("WordZap Cloudflare client cutover contract OK");
