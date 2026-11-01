// Adds `.scrolled` class to <nav> when scrolled, and fades in `.reveal`
// elements as they enter the viewport.
const nav = document.getElementById('nav');
if (nav) {
  window.addEventListener(
    'scroll',
    () => nav.classList.toggle('scrolled', scrollY > 20),
    { passive: true }
  );
}

const obs = new IntersectionObserver(
  (entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting) {
        e.target.classList.add('on');
        obs.unobserve(e.target);
      }
    });
  },
  { threshold: 0.1, rootMargin: '0px 0px -32px 0px' }
);

document.querySelectorAll('.reveal').forEach((el) => obs.observe(el));
