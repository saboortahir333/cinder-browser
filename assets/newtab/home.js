// home.js - Firefox Home behavior implementation

const DEFAULT_SITES = [
  { name: 'Wikipedia', url: 'https://www.wikipedia.org' },
  { name: 'GitHub', url: 'https://github.com' },
  { name: 'Flutter', url: 'https://flutter.dev' },
  { name: 'Rust', url: 'https://www.rust-lang.org' },
  { name: 'YouTube', url: 'https://www.youtube.com' },
  { name: 'Reddit', url: 'https://www.reddit.com' },
  { name: 'Supabase', url: 'https://supabase.com' },
  { name: 'X', url: 'https://x.com' }
];

const STORAGE_KEY = 'cinder_home_top_sites';

function getStoredSites() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed) && parsed.length > 0) return parsed;
    }
  } catch (e) {
    console.warn('Failed to read top sites from localStorage', e);
  }
  return [...DEFAULT_SITES];
}

function saveStoredSites(sites) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(sites));
  } catch (e) {
    console.warn('Failed to save top sites to localStorage', e);
  }
}

function getFaviconUrl(url) {
  try {
    const host = new URL(url).hostname;
    return `https://www.google.com/s2/favicons?domain=${encodeURIComponent(host)}&sz=128`;
  } catch (_) {
    return '';
  }
}

function navigate(url) {
  if (window.chrome && window.chrome.webview) {
    window.chrome.webview.postMessage({ type: 'navigate', url });
  } else {
    window.location.href = url;
  }
}
function renderTopSites() {
  const grid = document.getElementById('top-sites-grid');
  if (!grid) return;
  grid.innerHTML = '';

  const sites = getStoredSites();

  sites.forEach((site, index) => {
    const li = document.createElement('li');
    li.className = 'site-tile';

    const btn = document.createElement('button');
    btn.className = 'site-tile-button';
    btn.setAttribute('aria-label', `Open ${site.name}`);
    btn.addEventListener('click', () => navigate(site.url));

    const iconSpan = document.createElement('span');
    iconSpan.className = 'site-icon';

    const faviconUrl = getFaviconUrl(site.url);
    if (faviconUrl) {
      const img = document.createElement('img');
      img.src = faviconUrl;
      img.alt = '';
      img.onerror = () => {
        img.remove();
        iconSpan.textContent = (site.name || 'W')[0].toUpperCase();
      };
      iconSpan.appendChild(img);
    } else {
      iconSpan.textContent = (site.name || 'W')[0].toUpperCase();
    }

    const labelSpan = document.createElement('span');
    labelSpan.className = 'site-label';
    labelSpan.textContent = site.name;

    btn.appendChild(iconSpan);
    btn.appendChild(labelSpan);
    li.appendChild(btn);

    const editBtn = document.createElement('button');
    editBtn.className = 'site-tile-edit';
    editBtn.setAttribute('aria-label', `Edit ${site.name}`);
    editBtn.innerHTML = `
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path>
        <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path>
      </svg>
    `;
    editBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      editSite(index);
    });
    li.appendChild(editBtn);

    grid.appendChild(li);
  });

  const addLi = document.createElement('li');
  addLi.className = 'site-tile site-tile-add';

  const addBtn = document.createElement('button');
  addBtn.className = 'site-tile-button';
  addBtn.setAttribute('aria-label', 'Add shortcut');
  addBtn.innerHTML = `
    <span class="site-icon add-icon">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <line x1="12" y1="5" x2="12" y2="19"></line>
        <line x1="5" y1="12" x2="19" y2="12"></line>
      </svg>
    </span>
    <span class="site-label">Add shortcut</span>
  `;
  addBtn.addEventListener('click', () => promptAddSite());
  addLi.appendChild(addBtn);

  grid.appendChild(addLi);
}

function promptAddSite() {
  const name = prompt('Shortcut Name:');
  if (!name || !name.trim()) return;
  const url = prompt('Shortcut URL:', 'https://');
  if (!url || !url.trim()) return;

  let finalUrl = url.trim();
  if (!/^https?:\/\//i.test(finalUrl)) {
    finalUrl = 'https://' + finalUrl;
  }

  const sites = getStoredSites();
  sites.push({ name: name.trim(), url: finalUrl });
  saveStoredSites(sites);
  renderTopSites();
}

function editSite(index) {
  const sites = getStoredSites();
  const current = sites[index];
  if (!current) return;

  const action = prompt(`Edit shortcut "${current.name}":\nType "delete" to remove, or enter a new name:`, current.name);
  if (action === null) return;

  if (action.trim().toLowerCase() === 'delete') {
    sites.splice(index, 1);
    saveStoredSites(sites);
    renderTopSites();
    return;
  }

  const newName = action.trim();
  const newUrl = prompt('Shortcut URL:', current.url);
  if (newUrl === null) return;

  let finalUrl = newUrl.trim();
  if (finalUrl && !/^https?:\/\//i.test(finalUrl)) {
    finalUrl = 'https://' + finalUrl;
  }

  sites[index] = {
    name: newName || current.name,
    url: finalUrl || current.url
  };
  saveStoredSites(sites);
  renderTopSites();
}

function handleSearch(query) {
  const trimmed = query.trim();
  if (!trimmed) return;

  const hasScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(trimmed);
  const looksLikeUrl = hasScheme || (trimmed.includes('.') && !trimmed.includes(' '));
  let target;
  if (!looksLikeUrl) {
    target = `https://www.google.com/search?q=${encodeURIComponent(trimmed)}`;
  } else {
    target = hasScheme ? trimmed : `https://${trimmed}`;
  }
  navigate(target);
}

document.addEventListener('DOMContentLoaded', () => {
  renderTopSites();

  const searchForm = document.getElementById('search-form');
  const searchInput = document.getElementById('search-input');

  if (searchForm && searchInput) {
    searchForm.addEventListener('submit', (e) => {
      e.preventDefault();
      handleSearch(searchInput.value);
    });
  }
});

