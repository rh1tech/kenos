/* Mobile menu, staged reveal, and the light/dark screenshot switch.
 * No framework — pages stay readable with this file blocked. */
(function () {
  'use strict';

  // ── mobile menu ───────────────────────────────────────────────────────────
  var toggle = document.querySelector('.nav-toggle');
  var nav = document.getElementById('site-nav');

  if (toggle && nav) {
    toggle.addEventListener('click', function () {
      var open = nav.classList.toggle('open');
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    });

    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && nav.classList.contains('open')) {
        nav.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
        toggle.focus();
      }
    });

    nav.addEventListener('click', function (e) {
      if (e.target.tagName === 'A') {
        nav.classList.remove('open');
        toggle.setAttribute('aria-expanded', 'false');
      }
    });
  }

  // ── light / dark product shots ────────────────────────────────────────────
  document.querySelectorAll('.shots').forEach(function (figure) {
    var buttons = figure.querySelectorAll('.shot-switch [data-shot]');
    var shots = figure.querySelectorAll('.shot-stage .shot');
    if (!buttons.length || !shots.length) return;

    function show(name) {
      figure.setAttribute('data-shot', name);
      buttons.forEach(function (btn) {
        btn.setAttribute('aria-pressed', btn.getAttribute('data-shot') === name ? 'true' : 'false');
      });
      shots.forEach(function (shot) {
        shot.classList.toggle('is-active', shot.getAttribute('data-shot') === name);
      });
    }

    buttons.forEach(function (btn) {
      btn.addEventListener('click', function () {
        show(btn.getAttribute('data-shot'));
      });
    });
  });

  // ── staged reveal ─────────────────────────────────────────────────────────
  var targets = document.querySelectorAll('.reveal');
  if (!targets.length) return;

  var still = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (still || !('IntersectionObserver' in window)) {
    targets.forEach(function (el) { el.classList.add('in'); });
    return;
  }

  var seen = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('in');
      seen.unobserve(entry.target);
    });
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });

  targets.forEach(function (el) { seen.observe(el); });
})();
