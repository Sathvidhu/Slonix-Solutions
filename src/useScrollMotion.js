import { useLayoutEffect } from 'react'

// Enhance only after observation is available; content stays readable if JS fails.
export default function useScrollMotion(pageKey) {
  useLayoutEffect(() => {
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)')
    let observer, mutations, frame = 0
    const tracked = new Set()
    const root = document.documentElement
    const selectors = '.section-heading > div, .overlap-photo, .overlap-panel, .expertise-card, .industry-layout figure, .industry-list > a, .about-visual, .about-copy, .advantage-grid article, .delivery-card, .process-grid article, .global-layout > div, .project-card, .insights-photo, .insight-card, .cta-panel, .contact-layout > div, .contact-form, .service-detail > div:first-child, .capability-list > div, .related-services > a'

    const progress = () => {
      frame = 0
      const distance = root.scrollHeight - window.innerHeight
      root.style.setProperty('--scroll-progress', distance > 0 ? Math.min(1, Math.max(0, window.scrollY / distance)) : 0)
      tracked.forEach(el => {
        if (el.classList.contains('motion-visible') && el.getBoundingClientRect().top > window.innerHeight + 80) el.classList.remove('motion-visible')
      })
    }
    const onScroll = () => { if (!frame) frame = requestAnimationFrame(progress) }
    const clear = () => {
      observer?.disconnect()
      mutations?.disconnect()
      tracked.forEach(el => {
        el.classList.remove('motion-ready', 'motion-visible')
        el.removeAttribute('data-motion')
        el.style.removeProperty('--reveal-delay')
      })
      tracked.clear()
    }
    const setup = () => {
      clear()
      if (preference.matches || !('IntersectionObserver' in window)) return
      observer = new IntersectionObserver(entries => {
        entries.forEach(({ target, isIntersecting, boundingClientRect }) => {
          if (isIntersecting) target.classList.add('motion-visible')
          // Re-arm below the viewport so scrolling back down replays the entrance.
          else if (boundingClientRect.top > window.innerHeight) target.classList.remove('motion-visible')
        })
      }, { threshold: 0, rootMargin: '0px 0px -7% 0px' })
      const scan = () => {
        document.querySelectorAll(selectors).forEach(el => {
          if (tracked.has(el)) return
          tracked.add(el)
          const siblings = [...el.parentElement.children]
          const index = siblings.indexOf(el)
          const stagger = el.matches('.expertise-card, .advantage-grid article, .process-grid article, .project-card, .capability-list > div, .industry-list > a')
          el.style.setProperty('--reveal-delay', `${stagger ? index % 3 * 110 : 0}ms`)
          el.dataset.motion = el.matches('figure, .overlap-photo, .about-visual') ? 'image' : el.matches('.overlap-panel, .about-copy') ? 'side' : 'rise'
          el.classList.add('motion-ready')
          const bounds = el.getBoundingClientRect()
          if (bounds.top < window.innerHeight * .93) el.classList.add('motion-visible')
          observer.observe(el)
        })
      }
      scan()
      mutations = new MutationObserver(scan)
      mutations.observe(document.querySelector('main'), { childList: true, subtree: true })
    }
    setup()
    progress()
    preference.addEventListener('change', setup)
    window.addEventListener('scroll', onScroll, { passive: true })
    window.addEventListener('resize', onScroll)
    return () => {
      clear()
      cancelAnimationFrame(frame)
      preference.removeEventListener('change', setup)
      window.removeEventListener('scroll', onScroll)
      window.removeEventListener('resize', onScroll)
      root.style.removeProperty('--scroll-progress')
    }
  }, [pageKey])
}
