(function () {
  'use strict';

  function statusPill(status) {
    var map = {
      valid:       'pill pill-green',
      warning:     'pill pill-amber',
      critical:    'pill pill-red',
      expired:     'pill pill-red',
      unreachable: 'pill pill-amber'
    };
    return '<span class="' + (map[status] || 'pill') + '">' + (status || '-').toUpperCase() + '</span>';
  }

  function reachPill(reachable) {
    return reachable
      ? '<span class="pill pill-green">ONLINE</span>'
      : '<span class="pill pill-amber">OFFLINE</span>';
  }

  function daysLabel(days, status) {
    if (days === null || days === undefined) return '<span style="color:var(--text-muted)">-</span>';
    if (status === 'expired') {
      return '<span style="color:var(--red);font-weight:700;">' + Math.abs(days) + 'd overdue</span>';
    }
    var color = days < 15 ? 'var(--red)' : days < 60 ? 'var(--amber)' : 'var(--green)';
    return '<span style="color:' + color + ';font-weight:700;">' + days + 'd</span>';
  }

  function thumbCell(thumb) {
    if (!thumb) return '<span style="color:var(--text-muted)">-</span>';
    var short = thumb.substring(0, 16) + '...';
    return '<span style="font-family:\'JetBrains Mono\',monospace;font-size:0.68rem;color:var(--text-muted);cursor:default;" title="' + thumb + '">' + short + '</span>';
  }

  function dnCell(dn) {
    if (!dn) return '<span style="color:var(--text-muted)">-</span>';
    var cn = dn.match(/CN=([^,]+)/i);
    var display = cn ? cn[1] : dn;
    return '<span style="font-size:0.75rem;" title="' + escHtml(dn) + '">' + escHtml(display) + '</span>';
  }

  function emptyRow(cols, msg) {
    return '<tr><td colspan="' + cols + '" style="text-align:center;padding:20px;color:var(--text-muted);font-size:0.8rem;">' + msg + '</td></tr>';
  }

  function summaryGrid(items) {
    var html = '<div style="display:flex;gap:24px;flex-wrap:wrap;padding:12px 0 16px;">';
    items.forEach(function (item) {
      html += '<div style="display:flex;flex-direction:column;gap:2px;">'
            + '<span style="font-family:\'JetBrains Mono\',monospace;font-size:1.4rem;font-weight:800;color:' + item.color + ';text-shadow:0 0 10px ' + item.glow + ';">' + item.val + '</span>'
            + '<span style="font-size:0.65rem;letter-spacing:1.2px;text-transform:uppercase;color:var(--text-muted);">' + item.label + '</span>'
            + '</div>';
    });
    html += '</div>';
    return html;
  }

  function renderEnterpriseCAs(cas, summary) {
    var container  = document.getElementById('caCertEnterpriseTable');
    if (!container) return;
    var s        = summary || {};
    var sumHtml = summaryGrid([
      { val: s.total || 0,    label: 'Total',       color: 'var(--text-primary)', glow: 'transparent' },
      { val: s.valid || 0,    label: 'Valid',        color: 'var(--green)',        glow: 'var(--green-glow)' },
      { val: s.warning || 0,     label: 'Warning',      color: 'var(--amber)',        glow: 'var(--amber-glow)' },
      { val: s.critical || 0, label: 'Critical',     color: 'var(--red)',          glow: 'var(--red-glow)' },
      { val: s.expired || 0,  label: 'Expired',      color: 'var(--red)',          glow: 'var(--red-glow)' },
      { val: s.unreachable || 0,  label: 'Unreachable',  color: 'var(--amber)',        glow: 'var(--amber-glow)' }
    ]);
    var COLS = 9;
    if (!cas || cas.length === 0) {
      container.innerHTML = sumHtml + '<div class="table-container"><table class="data-table"><thead><tr><th>CA Name</th><th>Config</th><th>Reach</th><th>Status</th><th>Expiry Date</th><th>Days Left</th><th>Subject CN</th><th>Issuer CN</th><th>Thumbprint</th></tr></thead><tbody>' + emptyRow(COLS, 'No Enterprise CAs discovered') + '</tbody></table></div>';
      return;
    }
    var rows = '';
    cas.forEach(function (ca) {
      var rowBg = (ca.status === 'critical' || ca.status === 'expired') ? 'background:rgba(255,68,102,0.05);' : ca.status === 'warning' ? 'background:rgba(255,170,0,0.04);' : ca.status === 'unreachable' ? 'background:rgba(255,170,0,0.03);' : '';
      var leftBorder = (ca.status === 'critical' || ca.status === 'expired') ? 'box-shadow:inset 3px 0 0 var(--red);' : ca.status === 'warning' || ca.status === 'unreachable' ? 'box-shadow:inset 3px 0 0 var(--amber);' : ca.status === 'valid' ? 'box-shadow:inset 3px 0 0 var(--green);' : '';
      rows += '<tr style="' + rowBg + leftBorder + '">'
            + '<td><span style="font-family:\'JetBrains Mono\',monospace;font-weight:600;font-size:0.78rem;">' + escHtml(ca.caName || '-') + '</span></td>'
            + '<td style="color:var(--text-muted);font-size:0.7rem;">' + escHtml(ca.caConfig || '-') + '</td>'
            + '<td>' + reachPill(ca.reachable) + '</td><td>' + statusPill(ca.status) + '</td>'
            + '<td style="font-family:\'JetBrains Mono\',monospace;font-size:0.75rem;white-space:nowrap;">' + (ca.notAfter || '<span style="color:var(--text-muted)">-</span>') + '</td>'
            + '<td style="white-space:nowrap;">' + daysLabel(ca.daysRemaining, ca.status) + '</td>'
            + '<td>' + dnCell(ca.subject) + '</td><td>' + dnCell(ca.issuer) + '</td><td>' + thumbCell(ca.thumbprint) + '</td></tr>';
    });
    container.innerHTML = sumHtml + '<div class="table-container" style="max-height:420px;overflow-y:auto;"><table class="data-table"><thead><tr><th>CA Name</th><th>Config</th><th>Reach</th><th>Status</th><th>Expiry Date</th><th>Days Left</th><th>Subject CN</th><th>Issuer CN</th><th>Thumbprint</th></tr></thead><tbody>' + rows + '</tbody></table></div>';
  }

  function renderSelfSigned(certs, summary) {
    var container = document.getElementById('caCertSelfSignedTable');
    if (!container) return;
    var s        = summary || {};
    var sumHtml = summaryGrid([
      { val: s.total || 0,    label: 'Total',    color: 'var(--text-primary)', glow: 'transparent' },
      { val: s.valid || 0,    label: 'Valid',    color: 'var(--green)',        glow: 'var(--green-glow)' },
      { val: s.warning || 0,     label: 'Warning',  color: 'var(--amber)',        glow: 'var(--amber-glow)' },
      { val: s.critical || 0, label: 'Critical', color: 'var(--red)',          glow: 'var(--red-glow)' },
      { val: s.expired || 0,  label: 'Expired',  color: 'var(--red)',          glow: 'var(--red-glow)' }
    ]);
    var COLS = 8;
    if (!certs || certs.length === 0) {
      container.innerHTML = sumHtml + '<div class="table-container"><table class="data-table"><thead><tr><th>Friendly Name</th><th>Store</th><th>Status</th><th>Expiry Date</th><th>Days Left</th><th>Subject CN</th><th>Serial / Key Usage</th><th>Thumbprint</th></tr></thead><tbody>' + emptyRow(COLS, 'No self-signed certificates found') + '</tbody></table></div>';
      return;
    }
    var sorted = certs.slice().sort(function (a, b) {
      var rank = { expired: 0, critical: 1, warning: 2, valid: 3 };
      var ra = rank[a.status] !== undefined ? rank[a.status] : 4;
      var rb = rank[b.status] !== undefined ? rank[b.status] : 4;
      if (ra !== rb) return ra - rb;
      return (a.daysRemaining || 0) - (b.daysRemaining || 0);
    });
    var rows = '';
    sorted.forEach(function (cert) {
      var rowBg = (cert.status === 'critical' || cert.status === 'expired') ? 'background:rgba(255,68,102,0.05);' : cert.status === 'warning' ? 'background:rgba(255,170,0,0.04);' : '';
      var leftBorder = (cert.status === 'critical' || cert.status === 'expired') ? 'box-shadow:inset 3px 0 0 var(--red);' : cert.status === 'warning' ? 'box-shadow:inset 3px 0 0 var(--amber);' : cert.status === 'valid' ? 'box-shadow:inset 3px 0 0 var(--green);' : '';
      var storeBadgeColor = cert.store === 'My' ? 'background:rgba(0,212,255,0.1);color:var(--teal);border:1px solid rgba(0,212,255,0.2);' : cert.store === 'Root' ? 'background:rgba(168,85,247,0.1);color:#a855f7;border:1px solid rgba(168,85,247,0.25);' : 'background:var(--bg-elevated);color:var(--text-muted);border:1px solid var(--border-subtle);';
      var serialDisplay = cert.serialNumber ? '<span style="font-family:\'JetBrains Mono\',monospace;font-size:0.68rem;color:var(--text-muted);" title="' + escHtml(cert.serialNumber) + '">' + cert.serialNumber.substring(0, 12) + '...</span>' : '<span style="color:var(--text-muted)">-</span>';
      rows += '<tr style="' + rowBg + leftBorder + '">'
            + '<td><span style="font-family:\'JetBrains Mono\',monospace;font-weight:600;font-size:0.78rem;">' + escHtml(cert.friendlyName || '-') + '</span></td>'
            + '<td><span style="font-size:0.68rem;padding:2px 7px;border-radius:4px;' + storeBadgeColor + '">' + escHtml(cert.store || '-') + '</span></td>'
            + '<td>' + statusPill(cert.status) + '</td>'
            + '<td style="font-family:\'JetBrains Mono\',monospace;font-size:0.75rem;white-space:nowrap;">' + (cert.notAfter || '<span style="color:var(--text-muted)">-</span>') + '</td>'
            + '<td style="white-space:nowrap;">' + daysLabel(cert.daysRemaining, cert.status) + '</td>'
            + '<td>' + dnCell(cert.subject) + '</td><td>' + serialDisplay + '</td><td>' + thumbCell(cert.thumbprint) + '</td></tr>';
    });
    container.innerHTML = sumHtml + '<div class="table-container" style="max-height:460px;overflow-y:auto;"><table class="data-table"><thead><tr><th>Friendly Name</th><th>Store</th><th>Status</th><th>Expiry Date</th><th>Days Left</th><th>Subject CN</th><th>Serial</th><th>Thumbprint</th></tr></thead><tbody>' + rows + '</tbody></table></div>';
  }

  function escHtml(str) { return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }

  window.renderCACertExpiry = function (json) {
    var d = (json && json.caCertExpiry) ? json.caCertExpiry : json || {};
    renderEnterpriseCAs(d.cas || [], d.enterpriseSummary || {});
    renderSelfSigned(d.selfSigned || [], d.selfSignedSummary || {});
  };


  window.fetchCaData = function() {
    var uri = 'data/ca_data.json?t=' + new Date().getTime();
    fetch(uri, { cache: 'no-store' })
      .then(function(r){ return r.json(); })
      .then(function(data){
          if(window.renderCACertExpiry) window.renderCACertExpiry(data);
      })
      .catch(function(e){
          console.error('Failed to fetch ca_data.json', e);
          var errHtml = '<div style="padding:40px; text-align:center; color:var(--text-muted); font-size:0.85rem;">No CA telemetry payload found. Verify CACertCollect scheduled task is running successfully.</div>';
          var ent = document.getElementById('caCertEnterpriseTable');
          var ssl = document.getElementById('caCertSelfSignedTable');
          if (ent) ent.innerHTML = errHtml;
          if (ssl) ssl.innerHTML = errHtml;
      });
  };
})();