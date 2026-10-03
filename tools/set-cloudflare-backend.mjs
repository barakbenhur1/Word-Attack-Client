import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const plistPath = path.join(repoRoot, "Word-Guess-Info.plist");
let plist = fs.readFileSync(plistPath, "utf8");

function removeKey(xml, key) {
  const escaped = key.replace(/[.*+?^$()|[\]\\{}]/g, "\\$&");
  return xml.replace(
    new RegExp(
      "\\n?\\t?<key>" + escaped + "<\\/key>\\s*(?:<string>[\\s\\S]*?<\\/string>|<true\\s*\\/>|<false\\s*\\/>)\\s*",
      "g"
    ),
    "\n"
  );
}

plist = removeKey(plist, "WORDZAP_API_BASE_URL");
plist = removeKey(plist, "WORDZAP_NATIVE_PVP");

if (process.argv.includes("--rollback")) {
  fs.writeFileSync(plistPath, plist);
  console.log("Removed Cloudflare backend override; client will use the legacy Render fallback.");
  process.exit(0);
}

const raw = String(process.argv[2] || process.env.WORDZAP_API_BASE_URL || "").trim();
if (!raw) {
  throw new Error("Pass the accepted Cloudflare base URL, e.g. node tools/set-cloudflare-backend.mjs https://wordzap-api.example.workers.dev");
}

let url;
try { url = new URL(raw); }
catch { throw new Error("Invalid backend URL: " + raw); }

if (url.protocol !== "https:") throw new Error("Production backend URL must use https.");
if (url.username || url.password || url.search || url.hash) {
  throw new Error("Backend URL must not contain credentials, query parameters, or a fragment.");
}
url.pathname = url.pathname.replace(/\/+$/, "");
const normalized = url.toString().replace(/\/$/, "");

const skipLiveCheck = process.argv.includes("--skip-live-check");

async function fetchJson(pathname) {
  const response = await fetch(normalized + pathname, {
    headers: {accept:"application/json"},
    signal: AbortSignal.timeout(15000)
  });
  const text = await response.text();
  let body;
  try { body = JSON.parse(text); }
  catch { throw new Error(pathname + " returned non-JSON: " + text.slice(0,200)); }
  if (!response.ok) {
    throw new Error(pathname + " returned HTTP " + response.status + ": " + text.slice(0,300));
  }
  return body;
}

if (!skipLiveCheck) {
  const health = await fetchJson("/healthz");
  if (
    health?.ok !== true ||
    health?.hosting !== "cloudflare-workers" ||
    health?.storage !== "d1" ||
    health?.pvp !== "durable-object-websocket"
  ) {
    throw new Error("Cloudflare backend health contract failed; refusing to modify production plist.");
  }

  const ready = await fetchJson("/ready");
  if (ready?.ok !== true || ready?.storage !== "ready") {
    throw new Error("Cloudflare D1 readiness failed; refusing to modify production plist.");
  }

  const aiHealth = await fetchJson("/ai/health");
  if (aiHealth?.ok !== true) {
    throw new Error("Cloudflare AI health failed; refusing to modify production plist.");
  }

  const pushHealth = await fetchJson("/push/health");
  if (pushHealth?.ok !== true || pushHealth?.configured !== true) {
    const missing = Array.isArray(pushHealth?.missing) && pushHealth.missing.length
      ? " Missing: " + pushHealth.missing.join(", ")
      : "";
    throw new Error("Cloudflare APNs readiness failed; refusing to modify production plist." + missing);
  }

  console.log("Live Cloudflare acceptance passed before client cutover.");
}

const xmlEscape = value => String(value)
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&apos;");

const insertion =
  "\t<key>WORDZAP_API_BASE_URL</key>\n" +
  "\t<string>" + xmlEscape(normalized) + "</string>\n" +
  "\t<key>WORDZAP_NATIVE_PVP</key>\n" +
  "\t<true/>\n";

if (!plist.includes("</dict>")) throw new Error("Word-Guess-Info.plist is malformed: missing </dict>.");
plist = plist.replace("</dict>", insertion + "</dict>");
fs.writeFileSync(plistPath, plist);

console.log("WordZap backend override set to " + normalized);
console.log("Native Cloudflare PVP enabled.");
