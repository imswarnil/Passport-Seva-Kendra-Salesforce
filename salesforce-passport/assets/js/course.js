/* Site behaviour. Progressive enhancement only — every page is fully readable
   and navigable with this file blocked. */
(function () {
  'use strict';

  var root = document.documentElement;
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* ---- Theme toggle ---------------------------------------------------- */
  /* The inline script in <head> has already applied any stored preference.
     Here we only handle clicks, and store the *result* so the choice sticks. */
  function currentTheme() {
    var set = root.getAttribute('data-theme');
    if (set) return set;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  document.addEventListener('click', function (e) {
    if (!e.target.closest('[data-theme-toggle]')) return;
    var next = currentTheme() === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('theme', next); } catch (err) {}
  });

  /* ---- Mobile site nav ------------------------------------------------- */
  document.addEventListener('click', function (e) {
    var btn = e.target.closest('[data-nav-toggle]');
    if (!btn) return;
    var open = document.body.classList.toggle('nav-open');
    btn.setAttribute('aria-expanded', String(open));
  });

  /* ---- Course sidebar -------------------------------------------------- */
  var sidebar = document.getElementById('course-sidebar');
  var scrim = document.querySelector('.course__scrim');

  function setSidebar(open) {
    if (!sidebar) return;
    document.body.classList.toggle('sidebar-open', open);
    if (scrim) scrim.hidden = !open;
    var opener = document.querySelector('[data-sidebar-open]');
    if (opener) opener.setAttribute('aria-expanded', String(open));
  }

  document.addEventListener('click', function (e) {
    if (e.target.closest('[data-sidebar-open]')) setSidebar(true);
    else if (e.target.closest('[data-sidebar-close]')) setSidebar(false);
  });

  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    setSidebar(false);
    document.body.classList.remove('nav-open');
  });

  /* Keep the current lesson visible in a long sidebar without scrolling the
     whole page to it. */
  var current = document.querySelector('.lesson-link.is-current');
  if (current && sidebar) {
    var nav = sidebar.querySelector('.sidebar__nav');
    if (nav) {
      var delta = current.offsetTop - nav.offsetTop - (nav.clientHeight / 2);
      if (delta > 0) nav.scrollTop = delta;
    }
  }

  /* ---- Scroll reveal --------------------------------------------------- */
  var reveals = document.querySelectorAll('[data-reveal]');
  if (reveals.length) {
    if (reduced || !('IntersectionObserver' in window)) {
      reveals.forEach(function (el) { el.classList.add('is-in'); });
    } else {
      var revealObserver = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add('is-in');
          revealObserver.unobserve(entry.target);   /* animate once, then stop */
        });
      }, { rootMargin: '0px 0px -8% 0px', threshold: 0.05 });
      reveals.forEach(function (el) { revealObserver.observe(el); });
    }
  }

  /* ---- Table of contents ----------------------------------------------- */
  var tocEl = document.querySelector('[data-toc]');
  var list = document.querySelector('[data-toc-list]');
  var body = document.getElementById('lesson-body');
  if (!tocEl || !list || !body) return;

  var headings = Array.prototype.slice.call(body.querySelectorAll('h2, h3'));
  if (headings.length < 2) { tocEl.hidden = true; return; }

  headings.forEach(function (h, i) {
    if (!h.id) {
      h.id = (h.textContent || '')
        .toLowerCase().trim()
        .replace(/[^\w\s-]/g, '')
        .replace(/\s+/g, '-') || ('section-' + i);
    }
    var li = document.createElement('li');
    li.className = 'toc__item toc__item--' + h.tagName.toLowerCase();
    var a = document.createElement('a');
    a.href = '#' + h.id;
    a.textContent = h.textContent;
    a.dataset.tocLink = h.id;
    li.appendChild(a);
    list.appendChild(li);
  });

  var links = {};
  list.querySelectorAll('[data-toc-link]').forEach(function (a) {
    links[a.dataset.tocLink] = a;
  });

  var active = null;
  function activate(id) {
    if (id === active) return;
    if (active && links[active]) links[active].classList.remove('is-active');
    active = id;
    if (links[id]) links[id].classList.add('is-active');
  }

  if ('IntersectionObserver' in window) {
    var seen = new Set();
    var spy = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) seen.add(entry.target.id);
        else seen.delete(entry.target.id);
      });
      /* Highlight the topmost heading on screen; if none is, keep the last one
         we passed rather than clearing the whole TOC. */
      for (var i = 0; i < headings.length; i++) {
        if (seen.has(headings[i].id)) { activate(headings[i].id); return; }
      }
    }, { rootMargin: '-80px 0px -70% 0px', threshold: 0 });

    headings.forEach(function (h) { spy.observe(h); });
  }
})();
