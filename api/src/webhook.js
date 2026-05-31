const https = require("node:https");
const http = require("node:http");
const { URL } = require("node:url");

async function sendWebhook(webhookUrl, payload) {
  if (!webhookUrl) return;
  const body = JSON.stringify({
    service: "chromium-fleet",
    ...payload,
    timestamp: new Date().toISOString()
  });
  try {
    const url = new URL(webhookUrl);
    const lib = url.protocol === "https:" ? https : http;
    await new Promise((resolve) => {
      const req = lib.request(
        {
          hostname: url.hostname,
          port: url.port || (url.protocol === "https:" ? 443 : 80),
          path: url.pathname + url.search,
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Content-Length": Buffer.byteLength(body),
            "User-Agent": "chromium-fleet-api/1.0"
          }
        },
        (res) => { res.resume(); resolve(); }
      );
      req.on("error", resolve);
      req.setTimeout(8_000, () => { req.destroy(); resolve(); });
      req.write(body);
      req.end();
    });
  } catch {
    // non-fatal
  }
}

module.exports = { sendWebhook };
