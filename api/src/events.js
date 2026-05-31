const MAX_EVENTS_PER_SELLER = 50;
const _events = new Map();

function recordEvent(seller, type, data) {
  if (!_events.has(seller)) _events.set(seller, []);
  const list = _events.get(seller);
  list.unshift({ type, ...(data || {}), timestamp: new Date().toISOString() });
  if (list.length > MAX_EVENTS_PER_SELLER) list.length = MAX_EVENTS_PER_SELLER;
}

function getEvents(seller) {
  return _events.get(seller) || [];
}

module.exports = { recordEvent, getEvents };
