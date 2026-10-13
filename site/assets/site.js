/* Presentation-only interactions. Only a language preference is persisted. No model requests or analytics. */
(() => {
  'use strict';
  const one = (selector) => document.querySelector(selector);
  const all = (selector) => [...document.querySelectorAll(selector)];
  const uiNode = one('#ui-data');
  const ui = uiNode ? JSON.parse(uiNode.textContent) : {};
  const languageKey = 'quillside.website.language';
  all('[data-locale]').filter(link => link.tagName === 'A').forEach(link => {
    const pageURL = link.href;
    link.addEventListener('click', () => {
      const url = new URL(pageURL); url.hash = location.hash; link.href = url.href;
      try { localStorage.setItem(languageKey, link.dataset.locale); } catch (_) { /* Navigation also works without storage. */ }
    });
  });
  if (document.documentElement.dataset.rootAlias === 'true') {
    try {
      const saved = localStorage.getItem(languageKey);
      if (ui.locales?.includes(saved) && saved !== document.documentElement.lang) {
        const destination = one(`link[rel="alternate"][hreflang="${saved}"]`);
        if (destination) { const url = new URL(destination.href); url.hash = location.hash; location.replace(url.href); return; }
      }
    } catch (_) { /* Private browsing or blocked storage does not prevent reading. */ }
  }
  const languageMenu = one('.language-switch');
  if (languageMenu) {
    document.addEventListener('click', event => { if (!languageMenu.contains(event.target)) languageMenu.open = false; });
    languageMenu.addEventListener('keydown', event => { if (event.key === 'Escape') { languageMenu.open = false; languageMenu.querySelector('summary').focus(); } });
  }
  const paragraphNodes = (target, text) => {
    target.replaceChildren(...text.split('\n').filter(Boolean).map(line => {
      const p = document.createElement('p'); p.textContent = line; return p;
    }));
  };
  const dataNode = one('#scene-data');
  if (dataNode) {
    const examples = JSON.parse(dataNode.textContent);
    const titles = ui.sceneTitles;
    const descriptions = ui.sceneDescriptions;
    const tabs = all('[data-role]');
    const showRole = index => {
      const role = examples.roles[index];
      tabs.forEach((tab, i) => { tab.setAttribute('aria-selected', String(i === index)); tab.tabIndex = i === index ? 0 : -1; });
      one('#scene-panel').setAttribute('aria-labelledby', tabs[index].id);
      one('#scene-title').textContent = titles[index];
      one('#scene-description').textContent = descriptions[index];
      one('#scene-role-label').textContent = role.role;
      one('#role-prompt').textContent = role.prompt;
      paragraphNodes(one('#scene-candidate'), role.candidate);
    };
    tabs.forEach((tab, index) => {
      tab.addEventListener('click', () => showRole(index));
      tab.addEventListener('keydown', event => {
        let next;
        if (event.key === 'ArrowRight') next = (index + 1) % tabs.length;
        else if (event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
        else if (event.key === 'Home') next = 0;
        else if (event.key === 'End') next = tabs.length - 1;
        else return;
        event.preventDefault(); showRole(next); tabs[next].focus();
      });
    });
    paragraphNodes(one('#scene-source'), examples.source);
    showRole(0);
  }
  if (one('#comment-bubble')) {
    const comments = [...ui.comments];
    let selected = 0;
    const marks = all('[data-comment]');
    const setStatus = text => { one('#demo-status').textContent = text; };
    const openComment = index => {
      selected = index;
      one('#comment-input').value = comments[index];
      one('#comment-index').textContent = String(index + 1).padStart(2, '0');
      one('#comment-bubble').hidden = false;
      one('#demo-review').hidden = true;
      one('#optimize-demo').hidden = false;
      one('#demo-original').inert = false;
      marks.forEach((mark, i) => mark.setAttribute('aria-expanded', String(i === index)));
      setStatus(ui.editComment);
    };
    marks.forEach((mark, index) => mark.addEventListener('click', () => { openComment(index); one('#comment-input').focus(); }));
    one('#save-comment').addEventListener('click', () => {
      const input = one('#comment-input');
      if (!input.value.trim()) { setStatus(ui.emptyComment); input.focus(); return; }
      comments[selected] = input.value.trim();
      setStatus(ui.commentSaved);
    });
    one('#optimize-demo').addEventListener('click', () => {
      one('#comment-bubble').hidden = true;
      one('#demo-original').inert = true;
      marks.forEach(mark => mark.setAttribute('aria-expanded', 'false'));
      one('#demo-review').hidden = false;
      one('#optimize-demo').hidden = true;
      setStatus(ui.presetResult);
      one('#apply-demo').focus({preventScroll: true});
    });
    one('#back-to-comment').addEventListener('click', () => { openComment(selected); one('#optimize-demo').hidden = false; one('#comment-input').focus({preventScroll: true}); });
    one('#apply-demo').addEventListener('click', () => {
      one('#demo-review').hidden = true; one('#demo-original').hidden = true; one('#demo-applied').hidden = false;
      one('#reset-demo').hidden = false; one('#optimize-demo').hidden = true;
      setStatus(ui.applied);
      one('#reset-demo').focus({preventScroll: true});
    });
    one('#reset-demo').addEventListener('click', () => {
      one('#demo-original').hidden = false; one('#demo-applied').hidden = true;
      one('#reset-demo').hidden = true; one('#optimize-demo').hidden = false;
      openComment(selected); setStatus(ui.restored);
      one('#comment-input').focus({preventScroll: true});
    });
  }
  const editSamples = ui.editSamples;
  all('[data-edit]').forEach(button => button.addEventListener('click', () => {
    const sample = editSamples[button.dataset.edit];
    all('[data-edit]').forEach(item => { const active = item === button; item.classList.toggle('active', active); item.setAttribute('aria-pressed', String(active)); });
    const preview = one('#edit-preview');
    const command = document.createElement('span'); command.className = 'typing-command'; command.textContent = sample.command;
    const title = document.createElement('h3'); title.textContent = sample.title;
    const description = document.createElement('p'); description.textContent = sample.description; description.style.whiteSpace = 'pre-line';
    preview.replaceChildren(command, title, description);
    const active = one('#edit-menu-active'); active.querySelector('strong').textContent = sample.icon; active.querySelector('span').textContent = sample.label;
  }));
})();
