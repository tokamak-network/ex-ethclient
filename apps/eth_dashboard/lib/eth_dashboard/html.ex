defmodule EthDashboard.Html do
  @moduledoc """
  Serves the complete, self-contained dashboard HTML page.

  All CSS and JavaScript are inlined so no external assets are needed.
  The page connects to `/events` via Server-Sent Events for real-time
  updates every second.
  """

  @doc "Returns the full HTML dashboard page as a string."
  @spec page() :: String.t()
  def page do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>ex_ethclient Dashboard</title>
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', 'JetBrains Mono', monospace;
          background: #0d1117;
          color: #c9d1d9;
          padding: 20px;
          min-height: 100vh;
        }

        .header {
          text-align: center;
          padding: 20px 0;
          border-bottom: 1px solid #30363d;
          margin-bottom: 20px;
        }
        .header h1 {
          font-size: 24px;
          color: #58a6ff;
          letter-spacing: 1px;
        }
        .header .subtitle {
          color: #484f58;
          font-size: 12px;
          margin-top: 4px;
        }
        .header .uptime {
          color: #8b949e;
          font-size: 14px;
          margin-top: 8px;
        }
        .connection-status {
          display: inline-block;
          padding: 2px 10px;
          border-radius: 12px;
          font-size: 11px;
          margin-top: 8px;
        }
        .connection-connected { background: #238636; color: #f0f6fc; }
        .connection-disconnected { background: #da3633; color: #f0f6fc; }

        .grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 16px;
          max-width: 1200px;
          margin: 0 auto;
        }

        .card {
          background: #161b22;
          border: 1px solid #30363d;
          border-radius: 8px;
          padding: 16px;
          transition: border-color 0.2s ease;
        }
        .card:hover {
          border-color: #484f58;
        }
        .card h2 {
          font-size: 13px;
          color: #8b949e;
          text-transform: uppercase;
          letter-spacing: 1.5px;
          margin-bottom: 12px;
          display: flex;
          align-items: center;
          gap: 8px;
        }
        .card.full-width { grid-column: span 2; }

        .stat-value {
          font-size: 28px;
          font-weight: bold;
          color: #f0f6fc;
          transition: color 0.3s ease;
        }
        .stat-label {
          font-size: 11px;
          color: #8b949e;
          text-transform: uppercase;
          letter-spacing: 0.5px;
          margin-top: 2px;
        }
        .stat-row {
          display: flex;
          gap: 32px;
          margin-bottom: 12px;
          flex-wrap: wrap;
        }
        .stat-item {
          min-width: 100px;
        }

        .progress-bar {
          height: 8px;
          background: #21262d;
          border-radius: 4px;
          overflow: hidden;
          margin: 8px 0;
          position: relative;
        }
        .progress-fill {
          height: 100%;
          background: linear-gradient(90deg, #58a6ff, #3fb950);
          border-radius: 4px;
          transition: width 0.8s cubic-bezier(0.4, 0, 0.2, 1);
          position: relative;
        }
        .progress-fill::after {
          content: '';
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background: linear-gradient(
            90deg,
            transparent 0%,
            rgba(255,255,255,0.1) 50%,
            transparent 100%
          );
          animation: shimmer 2s infinite;
        }
        @keyframes shimmer {
          0% { transform: translateX(-100%); }
          100% { transform: translateX(100%); }
        }
        .progress-label {
          font-size: 11px;
          color: #8b949e;
          text-align: right;
          margin-top: 4px;
        }

        .status-badge {
          display: inline-block;
          padding: 3px 10px;
          border-radius: 12px;
          font-size: 12px;
          font-weight: bold;
          letter-spacing: 0.5px;
        }
        .status-idle { background: #21262d; color: #8b949e; }
        .status-syncing { background: #d29922; color: #0d1117; }
        .status-synced { background: #238636; color: #f0f6fc; }

        .peer-list, .block-list, .engine-list {
          font-size: 13px;
          max-height: 220px;
          overflow-y: auto;
          scrollbar-width: thin;
          scrollbar-color: #30363d #161b22;
        }
        .peer-list::-webkit-scrollbar,
        .block-list::-webkit-scrollbar,
        .engine-list::-webkit-scrollbar {
          width: 6px;
        }
        .peer-list::-webkit-scrollbar-track,
        .block-list::-webkit-scrollbar-track,
        .engine-list::-webkit-scrollbar-track {
          background: #161b22;
        }
        .peer-list::-webkit-scrollbar-thumb,
        .block-list::-webkit-scrollbar-thumb,
        .engine-list::-webkit-scrollbar-thumb {
          background: #30363d;
          border-radius: 3px;
        }

        .peer-row, .block-row, .engine-row {
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 6px 0;
          border-bottom: 1px solid #21262d;
        }
        .peer-row:last-child, .block-row:last-child, .engine-row:last-child {
          border-bottom: none;
        }

        .engine-status-VALID { color: #3fb950; font-weight: bold; }
        .engine-status-INVALID { color: #f85149; font-weight: bold; }
        .engine-status-SYNCING { color: #d29922; font-weight: bold; }

        .empty-state {
          color: #484f58;
          font-style: italic;
          padding: 20px 0;
          text-align: center;
          font-size: 13px;
        }

        .dot {
          display: inline-block;
          width: 8px; height: 8px;
          border-radius: 50%;
          margin-right: 6px;
          flex-shrink: 0;
        }
        .dot-green { background: #3fb950; box-shadow: 0 0 4px #3fb950; }
        .dot-yellow { background: #d29922; }
        .dot-red { background: #f85149; }
        .dot-gray { background: #484f58; }

        .network-stats {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 16px;
        }
        .network-stat {
          text-align: center;
          padding: 12px;
          background: #0d1117;
          border-radius: 6px;
          border: 1px solid #21262d;
        }

        @media (max-width: 768px) {
          .grid { grid-template-columns: 1fr; }
          .card.full-width { grid-column: span 1; }
          .stat-row { gap: 16px; }
        }
      </style>
    </head>
    <body>
      <div class="header">
        <h1>&#x27E0; ex_ethclient</h1>
        <div class="subtitle">Ethereum Execution Client Dashboard</div>
        <div class="uptime" id="uptime">00:00:00</div>
        <div class="connection-status connection-disconnected" id="conn-status">CONNECTING</div>
      </div>

      <div class="grid">
        <!-- Sync -->
        <div class="card full-width">
          <h2>Sync</h2>
          <div class="stat-row">
            <div class="stat-item">
              <div class="stat-value" id="current-block">0</div>
              <div class="stat-label">Current Block</div>
            </div>
            <div class="stat-item">
              <div class="stat-value" id="target-block">0</div>
              <div class="stat-label">Target Block</div>
            </div>
            <div class="stat-item">
              <div class="stat-value" id="blocks-per-sec">0</div>
              <div class="stat-label">Blocks/sec</div>
            </div>
            <div class="stat-item">
              <span class="status-badge status-idle" id="sync-status">idle</span>
            </div>
          </div>
          <div class="progress-bar">
            <div class="progress-fill" id="sync-progress" style="width: 0%"></div>
          </div>
          <div class="progress-label" id="sync-pct">0.00%</div>
        </div>

        <!-- Peers -->
        <div class="card">
          <h2>Peers <span class="stat-value" style="font-size:16px;margin-left:8px" id="peer-count">0</span></h2>
          <div class="peer-list" id="peer-list">
            <div class="empty-state">No peers connected</div>
          </div>
        </div>

        <!-- Engine API -->
        <div class="card">
          <h2>Engine API</h2>
          <div class="engine-list" id="engine-list">
            <div class="empty-state">Waiting for CL requests...</div>
          </div>
        </div>

        <!-- Recent Blocks -->
        <div class="card">
          <h2>Recent Blocks</h2>
          <div class="block-list" id="block-list">
            <div class="empty-state">No blocks yet</div>
          </div>
        </div>

        <!-- System -->
        <div class="card">
          <h2>System</h2>
          <div class="stat-row">
            <div class="stat-item">
              <div class="stat-value" id="memory" style="font-size:20px">0 MB</div>
              <div class="stat-label">BEAM Memory</div>
            </div>
            <div class="stat-item">
              <div class="stat-value" id="processes" style="font-size:20px">0</div>
              <div class="stat-label">Processes</div>
            </div>
          </div>
          <div class="network-stats">
            <div class="network-stat">
              <div class="stat-value" id="msg-sent" style="font-size:18px;color:#58a6ff">0</div>
              <div class="stat-label">Messages Sent</div>
            </div>
            <div class="network-stat">
              <div class="stat-value" id="msg-recv" style="font-size:18px;color:#3fb950">0</div>
              <div class="stat-label">Messages Received</div>
            </div>
          </div>
        </div>
      </div>

      <script>
        let evtSource = null;
        let reconnectDelay = 1000;

        function connect() {
          evtSource = new EventSource('/events');

          evtSource.onopen = function() {
            const el = document.getElementById('conn-status');
            el.textContent = 'CONNECTED';
            el.className = 'connection-status connection-connected';
            reconnectDelay = 1000;
          };

          evtSource.onmessage = function(event) {
            try {
              const data = JSON.parse(event.data);
              update(data);
            } catch(e) {
              console.error('Failed to parse SSE data:', e);
            }
          };

          evtSource.onerror = function() {
            const el = document.getElementById('conn-status');
            el.textContent = 'DISCONNECTED';
            el.className = 'connection-status connection-disconnected';
            evtSource.close();
            setTimeout(connect, reconnectDelay);
            reconnectDelay = Math.min(reconnectDelay * 2, 10000);
          };
        }

        function update(d) {
          // Uptime
          const up = d.system.uptime;
          const h = Math.floor(up / 3600);
          const m = Math.floor((up % 3600) / 60);
          const s = up % 60;
          document.getElementById('uptime').textContent =
            pad(h) + ':' + pad(m) + ':' + pad(s);

          // Sync
          document.getElementById('current-block').textContent =
            d.sync.current_block.toLocaleString();
          document.getElementById('target-block').textContent =
            d.sync.target_block.toLocaleString();
          document.getElementById('blocks-per-sec').textContent =
            d.sync.blocks_per_sec;

          const statusEl = document.getElementById('sync-status');
          statusEl.textContent = d.sync.status;
          statusEl.className = 'status-badge status-' + d.sync.status;

          const pct = d.sync.target_block > 0
            ? (d.sync.current_block / d.sync.target_block * 100)
            : 0;
          document.getElementById('sync-progress').style.width =
            Math.min(pct, 100).toFixed(2) + '%';
          document.getElementById('sync-pct').textContent =
            pct.toFixed(2) + '%';

          // Peers
          document.getElementById('peer-count').textContent = d.peers.count;
          const peerList = document.getElementById('peer-list');
          if (d.peers.list.length === 0) {
            peerList.innerHTML = '<div class="empty-state">No peers connected</div>';
          } else {
            peerList.innerHTML = d.peers.list.map(function(p) {
              return '<div class="peer-row">' +
                '<span><span class="dot dot-green"></span>' +
                escapeHtml(p.ip) + ':' + (p.port || '') + '</span>' +
                '<span style="color:#8b949e;font-size:11px;max-width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' +
                escapeHtml((p.client || '').substring(0, 30)) + '</span>' +
                '</div>';
            }).join('');
          }

          // Engine API
          const engineList = document.getElementById('engine-list');
          if (d.engine.length === 0) {
            engineList.innerHTML = '<div class="empty-state">Waiting for CL requests...</div>';
          } else {
            engineList.innerHTML = d.engine.map(function(e) {
              return '<div class="engine-row">' +
                '<span style="color:#484f58;font-size:11px;min-width:60px">' + escapeHtml(e.time) + '</span>' +
                '<span style="flex:1;margin:0 8px">' + escapeHtml(e.method) + '</span>' +
                '<span class="engine-status-' + escapeHtml(e.status) + '">' + escapeHtml(e.status) + '</span>' +
                '</div>';
            }).join('');
          }

          // Blocks
          const blockList = document.getElementById('block-list');
          if (d.blocks.length === 0) {
            blockList.innerHTML = '<div class="empty-state">No blocks yet</div>';
          } else {
            blockList.innerHTML = d.blocks.map(function(b) {
              return '<div class="block-row">' +
                '<span style="color:#58a6ff;min-width:80px">#' + b.number.toLocaleString() + '</span>' +
                '<span style="color:#484f58;font-size:11px;flex:1">0x' + escapeHtml(b.hash) + '...</span>' +
                '<span style="min-width:50px;text-align:right">' + b.tx_count + ' tx</span>' +
                '<span style="color:#8b949e;min-width:70px;text-align:right">' + formatGas(b.gas_used) + '</span>' +
                '</div>';
            }).join('');
          }

          // System
          document.getElementById('memory').textContent = d.system.memory_mb + ' MB';
          document.getElementById('processes').textContent =
            d.system.processes.toLocaleString();
          document.getElementById('msg-sent').textContent =
            d.network.sent.toLocaleString();
          document.getElementById('msg-recv').textContent =
            d.network.received.toLocaleString();
        }

        function pad(n) { return String(Math.floor(n)).padStart(2, '0'); }

        function formatGas(g) {
          if (g >= 1e9) return (g / 1e9).toFixed(1) + 'G';
          if (g >= 1e6) return (g / 1e6).toFixed(1) + 'M';
          if (g >= 1e3) return (g / 1e3).toFixed(1) + 'K';
          return String(g);
        }

        function escapeHtml(str) {
          if (!str) return '';
          return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
        }

        connect();
      </script>
    </body>
    </html>
    """
  end
end
