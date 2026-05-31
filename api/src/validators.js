const SELLER_REGEX = /^[a-z0-9][a-z0-9_-]{0,31}$/;
const SUBDOMAIN_REGEX = /^[A-Za-z0-9.-]+$/;

function isValidSellerName(value) {
  return typeof value === "string" && SELLER_REGEX.test(value);
}

function isValidPort(value) {
  const n = Number.parseInt(String(value), 10);
  return Number.isInteger(n) && n >= 1 && n <= 65535;
}

function isValidSubdomain(value) {
  return typeof value === "string" && value.length > 0 && SUBDOMAIN_REGEX.test(value);
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
