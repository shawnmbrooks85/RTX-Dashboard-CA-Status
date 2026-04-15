(function () {
  'use strict';

  var DATA = null;
  var POLL_INTERVAL_MS = 60000;
  var pollTimer = null;
  var liveClockTimer = null;
  var DATA_PATH = 'data/ca_data.json';

  function relativeTime(iso) {
    if (!iso) return '-';
    var d = new Date(iso);
    var diff = Math.floor((Date.now() - d.getTime()) / 1000);
    if (diff < 5) return 'just now';
    if (diff < 60) return diff + 's ago';
    if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
    if (diff < 86400) return Math.floor(diff / 3600) + 'h ago';
    return Math.floor(diff / 86400) + 'd ago';
  }

  function startLiveClock() {
    var el = document.getElementById('liveClock');
    if (!el) return;
    function tick() {
      var now = new Date();
      el.textContent = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    }
    tick();
    liveClockTimer = setInterval(tick, 1000);
  }

  function updateHeader(d) {
    var lr = document.getElementById('lastRefresh');
    var db = document.getElementById('dataBadge');
    if (lr) lr.textContent = relativeTime(d.collectedAt || d.lastRefresh);
    if (db) {
      var es = d.enterpriseSummary || {};
      var bad = (es.critical || 0) + (es.expired || 0);
      var warn = (es.warning || 0) + (es.unreachable || 0);
      if (bad > 0) { db.textContent = bad + ' CRITICAL'; db.className = 'header-badge pill-red'; }
      else if (warn > 0) { db.textContent = warn + ' WARNING'; db.className = 'header-badge pill-amber'; }
      else { db.textContent = 'ALL VALID'; db.className = 'header-badge pill-green'; }
    }
  }

  function loadData() {
    return fetch(DATA_PATH + '?t=' + Date.now(), { cache: 'no-store', credentials: 'include' })
      .then(function (r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function (json) {
        DATA = json;
        if (DATA.caCertExpiry) {
          updateHeader(DATA.caCertExpiry);
        }
        if (window.renderCACertExpiry) {
          window.renderCACertExpiry(DATA);
        }
      })
      .catch(function (e) {
        console.warn('[CA Dashboard] Data load failed:', e.message);
      });
  }

  function startPolling() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(loadData, POLL_INTERVAL_MS);
  }

  function showDashboard() {
    var skeleton = document.getElementById('loadingSkeleton');
    var main     = document.getElementById('dashboardMain');
    if (skeleton) { skeleton.style.display = 'none'; skeleton.style.visibility = 'hidden'; }
    if (main)     { main.style.display = 'flex'; main.style.visibility = 'visible'; }
  }

  var THEMES = ['', 'frosty', 'light'];
  var THEME_LABELS = { '': 'Switch to Frosty Theme', 'frosty': 'Switch to Light Mode', 'light': 'Switch to Dark Mode' };

  function applyTheme(t) {
    document.documentElement.setAttribute('data-theme', t);
    try { localStorage.setItem('ca-dash-theme', t); } catch(e) {}
    var btn = document.getElementById('themeToggle');
    if (btn) { var sp = btn.querySelector('span'); if (sp) sp.textContent = THEME_LABELS[t] || 'Toggle Theme'; }
  }

  function initTheme() {
    var saved = '';
    try { saved = localStorage.getItem('ca-dash-theme') || ''; } catch(e) {}
    applyTheme(saved);
    var btn = document.getElementById('themeToggle');
    if (btn) {
      btn.addEventListener('click', function () {
        var cur = document.documentElement.getAttribute('data-theme') || '';
        var idx = THEMES.indexOf(cur);
        applyTheme(THEMES[(idx + 1) % THEMES.length]);
      });
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    initTheme();
    startLiveClock();

    var backToTop = document.getElementById('backToTop');
    window.addEventListener('scroll', function () {
      if (backToTop) backToTop.classList.toggle('visible', window.scrollY > 300);
    });
    if (backToTop) {
      backToTop.addEventListener('click', function () {
        window.scrollTo({ top: 0, behavior: 'smooth' });
      });
    }

    loadData().then(function () {
      showDashboard();
      startPolling();
    }).catch(function () {
      showDashboard();
    });

    setTimeout(function () { showDashboard(); }, 3000);
  });

})();
