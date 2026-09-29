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
