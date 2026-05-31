const SELLER_REGEX = /^[a-z0-9][a-z0-9_-]{0,31}$/;

function isValidSellerName(value) {
  return typeof value === "string" && SELLER_REGEX.test(value);
}

function isValidPort(value) {
  const n = Number.parseInt(String(value), 10);
  return Number.isInteger(n) && n >= 1 && n <= 65535;
}

function isValidSubdomain(value) {
  if (typeof value !== "string") {
    return false;
  }

  const domain = value.trim();
  if (!domain || domain.length > 253 || domain.startsWith(".") || domain.endsWith(".") || domain.includes("..")) {
    return false;
  }

  const labels = domain.split(".");
  if (labels.length < 2) {
    return false;
  }

  for (const label of labels) {
    if (
      label.length < 1 ||
      label.length > 63 ||
      !/^[A-Za-z0-9-]+$/.test(label) ||
      label.startsWith("-") ||
      label.endsWith("-")
    ) {
      return false;
    }
  }

  const tld = labels[labels.length - 1];
  return tld.length >= 2;
}

function isValidProxy(value) {
  if (typeof value !== "string") {
    return false;
  }

  const [host, port, user, pass, extra] = value.split(":");
  if (!host || !port || !user || !pass || extra) {
    return false;
  }

  return isValidPort(port);
}

module.exports = {
  isValidSellerName,
  isValidPort,
  isValidSubdomain,
  isValidProxy
};
