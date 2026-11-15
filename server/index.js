const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8081;
const wss = new WebSocketServer({ port: PORT });

// normalizedId (no spaces) -> { ws, password, viewers: Set<WebSocket> }
const hosts = new Map();

function normId(id) {
  return String(id || '').replace(/\s+/g, '');
}

wss.on('connection', (ws) => {
  let role = null; // 'host' | 'viewer'
  let hostId = null;
  let targetHostId = null;

  ws.on('message', (raw, isBinary) => {
    if (isBinary) {
      if (role === 'host' && hostId && hosts.has(hostId)) {
        for (const v of hosts.get(hostId).viewers) {
          if (v.readyState === 1) v.send(raw, { binary: true });
        }
      }
      return;
    }

    let msg;
    try { msg = JSON.parse(raw.toString()); } catch { return; }

    if (msg.type === 'register' && msg.id && msg.password) {
      role = 'host';
      hostId = normId(msg.id);
      hosts.set(hostId, { ws, password: String(msg.password), viewers: new Set() });
      ws.send(JSON.stringify({
        type: 'registered',
        id: hostId,
        iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
      }));
      return;
    }

    if (msg.type === 'connect' && msg.targetId && msg.password) {
      const tid = normId(msg.targetId);
      const h = hosts.get(tid);
      if (!h) {
        ws.send(JSON.stringify({ type: 'error', message: 'Không tìm thấy ID đối tác' }));
        return;
      }
      if (h.password !== String(msg.password)) {
        ws.send(JSON.stringify({ type: 'error', message: 'Sai mật khẩu' }));
        return;
      }
      role = 'viewer';
      targetHostId = tid;
      h.viewers.add(ws);
      ws.send(JSON.stringify({
        type: 'connected',
        targetId: tid,
        iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
      }));
      if (h.ws.readyState === 1) h.ws.send(JSON.stringify({ type: 'viewer-joined' }));
      return;
    }

    // WebRTC signaling relay (sdp-offer, sdp-answer, ice-candidate)
    if (msg.type === 'sdp-offer' || msg.type === 'sdp-answer' || msg.type === 'ice-candidate') {
      if (role === 'viewer' && targetHostId && hosts.has(targetHostId)) {
        const h = hosts.get(targetHostId);
        if (h.ws.readyState === 1) h.ws.send(raw.toString());
      } else if (role === 'host' && hostId && hosts.has(hostId)) {
        for (const v of hosts.get(hostId).viewers) {
          if (v.readyState === 1) v.send(raw.toString());
        }
      }
      return;
    }

    // Input control relay
    if (role === 'viewer' && targetHostId && hosts.has(targetHostId)) {
      const h = hosts.get(targetHostId);
      if (h.ws.readyState === 1) h.ws.send(raw.toString());
    }
  });

  ws.on('close', () => {
    if (role === 'host' && hostId) {
      const h = hosts.get(hostId);
      if (h) {
        for (const v of h.viewers) {
          if (v.readyState === 1) v.send(JSON.stringify({ type: 'host-disconnected' }));
        }
        hosts.delete(hostId);
      }
    } else if (role === 'viewer' && targetHostId && hosts.has(targetHostId)) {
      hosts.get(targetHostId).viewers.delete(ws);
    }
  });
});

console.log(`PC Remote Signaling & Relay server listening on :${PORT}`);
