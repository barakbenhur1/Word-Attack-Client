import fs from "node:fs";

const files = {
  config: fs.readFileSync("Word Guess/Network/BackendConfiguration.swift", "utf8"),
  network: fs.readFileSync("Word Guess/Network/Network.swift", "utf8"),
  pvp: fs.readFileSync("Word Guess/Network/ViewModel/VsPlayerGameViewModel.swift", "utf8"),
  native: fs.readFileSync("Word Guess/Network/NativePvPWebSocketClient.swift", "utf8")
};

function requireFragment(name, fragment) {
  if (!files[name].includes(fragment)) {
    throw new Error("Missing " + name + " fragment: " + fragment);
  }
}

requireFragment("config", "BackendConfiguration");
requireFragment("config", "WORDZAP_API_BASE_URL");
requireFragment("config", "WORDZAP_NATIVE_PVP");
requireFragment("config", "/pvp/socket");
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

// The legacy host is intentionally allowed only in the central fallback config.
// This prevents a partial cutover where REST and PVP silently point at different backends.
for (const [name, body] of Object.entries(files)) {
  if (name === "config") continue;
  if (body.includes("word-attack-server.onrender.com")) {
    throw new Error("Legacy Render URL is still hard-coded in " + name);
  }
}

console.log("WordZap Cloudflare client cutover contract OK");
