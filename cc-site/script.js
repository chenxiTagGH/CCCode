const menuToggle = document.querySelector('.menu-toggle');
const nav = document.querySelector('#site-nav');
const themeToggle = document.querySelector('.theme-toggle');

const savedTheme = localStorage.getItem('cccode-theme');
if (savedTheme === 'light') document.body.classList.add('light-theme');
const syncThemeButton = () => {
  const light = document.body.classList.contains('light-theme');
  themeToggle?.setAttribute('aria-pressed', String(light));
  themeToggle?.setAttribute('aria-label', light ? '切换深色主题' : '切换浅色主题');
  const label = themeToggle?.querySelector('.theme-toggle-label');
  if (label) label.textContent = light ? '深色' : '浅色';
  const icon = themeToggle?.querySelector('.theme-toggle-icon');
  if (icon) icon.textContent = light ? '◐' : '☼';
};
syncThemeButton();
themeToggle?.addEventListener('click', () => {
  document.body.classList.toggle('light-theme');
  localStorage.setItem('cccode-theme', document.body.classList.contains('light-theme') ? 'light' : 'dark');
  syncThemeButton();
  nav?.classList.remove('is-open');
  menuToggle?.setAttribute('aria-expanded', 'false');
});

menuToggle?.addEventListener('click', () => {
  const open = nav.classList.toggle('is-open');
  menuToggle.setAttribute('aria-expanded', String(open));
});

nav?.querySelectorAll('a').forEach((link) => link.addEventListener('click', () => {
  nav.classList.remove('is-open');
  menuToggle?.setAttribute('aria-expanded', 'false');
}));

document.addEventListener('click', (event) => {
  if (!nav?.classList.contains('is-open')) return;
  const target = event.target;
  if (target instanceof Node && !nav.contains(target) && !menuToggle?.contains(target)) {
    nav.classList.remove('is-open');
    menuToggle?.setAttribute('aria-expanded', 'false');
  }
});

document.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape' || !nav?.classList.contains('is-open')) return;
  nav.classList.remove('is-open');
  menuToggle?.setAttribute('aria-expanded', 'false');
  menuToggle?.focus();
});

