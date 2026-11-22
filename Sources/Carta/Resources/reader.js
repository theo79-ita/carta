(() => {
  'use strict';
  const reader = document.getElementById('reader');
  let previous = {};
  let headings = [];
  let activeHeadingID = null;
  let readingFrame = 0;
  let lastRemainingSeconds = null;
  let jumpDestination = null;
  let jumpTimer = 0;
  const post = body => window.webkit?.messageHandlers?.carta?.postMessage(body);
  const slug = text => text.toLowerCase().trim().replace(/[^\p{L}\p{N}\s_-]/gu, '').replace(/\s+/g, '-') || 'sezione';
  const headingOffset = () => parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop) || 0;
  const maxScrollY = () => Math.max(0, document.scrollingElement.scrollHeight - document.scrollingElement.clientHeight);
  const postReaderState = body => post({ documentID: previous.documentID, source: previous.source, ...body });

  function selectHeading(id) {
    if (activeHeadingID === id) return;
    activeHeadingID = id;
    postReaderState({ activeHeadingID });
  }

  function updateActiveHeading(bottom) {
    if (!headings.length) return;
    if (jumpDestination !== null) {
      // A click selects its exact heading, even when the document ends too soon to align it.
      if (Math.abs(window.scrollY - jumpDestination) <= 1) {
        clearTimeout(jumpTimer);
        jumpTimer = 0;
        return;
      }
      if (jumpTimer) return;
      jumpDestination = null;
    }

    if (bottom > 1 && window.scrollY >= bottom - 1) {
      selectHeading(headings[headings.length - 1].id);
      return;
    }
    const readingLine = headingOffset() + 1;
    let current = headings[0];
    for (const heading of headings) {
      if (heading.getBoundingClientRect().top <= readingLine) current = heading;
    }
    selectHeading(current.id);
  }

  function updateReadingPosition() {
    if (!previous.documentID) return;
    const bottom = maxScrollY();
    const y = Math.max(0, window.scrollY);
    // A document that fits in the window still needs to be read.
    const progress = bottom <= 1 ? 0 : (y >= bottom - 1 ? 1 : y / bottom);
    const remainingSeconds = Math.ceil(previous.readingSeconds * (1 - progress));
    if (remainingSeconds !== lastRemainingSeconds) {
      lastRemainingSeconds = remainingSeconds;
      postReaderState({ remainingSeconds });
    }
    updateActiveHeading(bottom);
  }

  function scheduleReadingUpdate() {
    if (readingFrame) return;
    readingFrame = requestAnimationFrame(() => {
      readingFrame = 0;
      updateReadingPosition();
    });
  }

  function waitForJumpToSettle() {
    clearTimeout(jumpTimer);
    jumpTimer = setTimeout(() => {
      jumpTimer = 0;
      scheduleReadingUpdate();
    }, 140);
  }

  window.addEventListener('scroll', () => {
    if (jumpTimer) waitForJumpToSettle();
    scheduleReadingUpdate();
  }, { passive: true });
  window.addEventListener('resize', scheduleReadingUpdate);
  new ResizeObserver(scheduleReadingUpdate).observe(reader);

  window.Carta = {
    render(payload) {
      document.documentElement.dataset.theme = payload.theme;
      document.documentElement.style.setProperty('--font-size', `${payload.fontSize}px`);
      if (previous.text === payload.text && previous.source === payload.source && previous.documentID === payload.documentID) {
        previous = payload;
        scheduleReadingUpdate();
        return;
      }
      const sameFile = previous.documentID === payload.documentID;
      const scrollY = window.scrollY;
      previous = payload;
      clearTimeout(jumpTimer);
      jumpTimer = 0;
      jumpDestination = null;
      activeHeadingID = null;
      headings = [];
      reader.classList.toggle('source', payload.source);
      lastRemainingSeconds = null;
      if (payload.source) {
        const pre = document.createElement('pre');
        pre.className = 'source-content';
        pre.textContent = payload.text;
        reader.replaceChildren(pre);
        postReaderState({ headings: [], activeHeadingID: null });
      } else {
        const html = marked.parse(payload.text, { gfm: true, breaks: false, async: false });
        reader.innerHTML = DOMPurify.sanitize(html, {
          USE_PROFILES: { html: true },
          FORBID_TAGS: ['style', 'form', 'button', 'textarea', 'select', 'video', 'audio', 'iframe', 'object', 'embed'],
          FORBID_ATTR: ['style', 'srcset', 'id', 'name'],
          ALLOW_DATA_ATTR: false
        });
        const seen = new Set();
        headings = [...reader.querySelectorAll('h1,h2,h3,h4,h5,h6')];
        const outline = headings.map(heading => {
          const base = slug(heading.textContent);
          let id = base, suffix = 1;
          while (seen.has(id)) id = `${base}-${suffix++}`;
          seen.add(id); heading.id = id;
          return { id, title: heading.textContent.trim(), level: Number(heading.tagName[1]) };
        });
        for (const input of reader.querySelectorAll('input')) { input.disabled = true; }
        for (const image of reader.querySelectorAll('img')) {
          const raw = image.getAttribute('src') || '';
          try {
            const url = new URL(raw, payload.assetBase);
            if (!['carta-asset:', 'https:', 'http:', 'data:'].includes(url.protocol)) { image.removeAttribute('src'); continue; }
            image.src = url.href;
            image.loading = 'lazy';
            image.referrerPolicy = 'no-referrer';
            image.addEventListener('error', () => {
              const fallback = document.createElement('span');
              fallback.className = 'image-fallback';
              fallback.textContent = `Immagine non disponibile${image.alt ? ': ' + image.alt : ''}`;
              image.replaceWith(fallback);
            }, { once: true });
          } catch { image.removeAttribute('src'); }
        }
        for (const link of reader.querySelectorAll('a[href]')) {
          const raw = link.getAttribute('href');
          link.removeAttribute('target');
          link.rel = 'noreferrer noopener';
          if (raw.startsWith('#')) {
            link.addEventListener('click', event => {
              event.preventDefault();
              try { window.Carta.scrollTo(decodeURIComponent(raw.slice(1))); } catch { /* Invalid anchor. */ }
            });
          } else {
            try {
              const url = new URL(raw, payload.documentURL || 'about:blank');
              if (['https:', 'http:', 'mailto:', 'file:'].includes(url.protocol)) link.href = url.href;
              else link.removeAttribute('href');
            } catch { link.removeAttribute('href'); }
          }
        }
        for (const pre of reader.querySelectorAll('pre')) {
          const code = pre.querySelector('code');
          if (!code) continue;
          const language = [...code.classList].find(c => c.startsWith('language-'))?.slice(9);
          const toolbar = document.createElement('div'); toolbar.className = 'code-toolbar';
          const label = document.createElement('span'); label.textContent = language || 'codice';
          const copy = document.createElement('button'); copy.textContent = 'Copia'; copy.title = 'Copia codice';
          copy.addEventListener('click', () => {
            post({ copy: code.textContent }); copy.textContent = 'Copiato';
            setTimeout(() => { copy.textContent = 'Copia'; }, 1400);
          });
          toolbar.append(label, copy); pre.prepend(toolbar);
        }
        for (const table of reader.querySelectorAll('table')) {
          const wrapper = document.createElement('div'); wrapper.className = 'table-scroll';
          wrapper.classList.toggle('wide-table', [...table.rows].some(row => row.cells.length >= 4));
          wrapper.tabIndex = 0;
          wrapper.setAttribute('role', 'region');
          wrapper.setAttribute('aria-label', 'Tabella, scorrimento orizzontale');
          table.before(wrapper); wrapper.append(table);
        }
        postReaderState({ headings: outline });
      }
      requestAnimationFrame(() => {
        if (previous.documentID !== payload.documentID || previous.text !== payload.text ||
            previous.source !== payload.source || jumpDestination !== null) return;
        window.scrollTo(0, sameFile ? scrollY : 0);
        updateReadingPosition();
      });
    },
    scrollTo(id) {
      const heading = headings.find(item => item.id === id);
      if (!heading) return;
      const top = heading.getBoundingClientRect().top + window.scrollY - headingOffset();
      jumpDestination = Math.min(maxScrollY(), Math.max(0, top));
      selectHeading(id);
      waitForJumpToSettle();
      window.scrollTo({ top: jumpDestination, behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
    }
  };
})();
