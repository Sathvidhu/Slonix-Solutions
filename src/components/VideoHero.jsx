import { useEffect, useRef, useState } from 'react'
import { company } from '../data'
import { Arrow } from './UI'

export default function VideoHero() {
  const video = useRef(null)
  const [reduced, setReduced] = useState(() => window.matchMedia('(prefers-reduced-motion: reduce)').matches)
  const [playing, setPlaying] = useState(false)
  const [failed, setFailed] = useState(false)
  const [notice, setNotice] = useState('')

  useEffect(() => {
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)')
    const update = () => setReduced(preference.matches)
    preference.addEventListener('change', update)
    return () => preference.removeEventListener('change', update)
  }, [])

  useEffect(() => {
    const media = video.current
    if (!media || reduced) return
    let active = true
    media.play().catch(() => {
      if (active && media.networkState !== HTMLMediaElement.NETWORK_NO_SOURCE) { media.autoplay = false; media.pause(); setPlaying(false); setNotice('Video paused. Select play to start the background video.') }
    })
    return () => { active = false; media.pause() }
  }, [reduced])

  async function toggle() {
    if (!video.current || failed) return
    if (playing) { video.current.pause(); setNotice('Background video paused.') }
    else {
      try { await video.current.play(); setNotice('Background video playing.') }
      catch { video.current.pause(); setNotice('Video could not play. The static background remains available.'); setPlaying(false) }
    }
  }

  return <section id="home" className="hero">
    <img className="hero-poster" src={company.heroPoster} alt="" width="1600" height="900" fetchPriority="high" />
    {!reduced && !failed && <video ref={video} className="hero-video" autoPlay muted loop playsInline preload="metadata" poster={company.heroPoster} aria-hidden="true" tabIndex={-1}
      onPlaying={() => { setPlaying(true); setNotice('') }} onPause={() => setPlaying(false)}
      onError={() => { setFailed(true); setPlaying(false); setNotice('Background video unavailable. Showing a static image.') }}>
      <source src={company.heroVideo} type="video/mp4" onError={() => { setFailed(true); setPlaying(false); setNotice('Background video unavailable. Showing a static image.') }} />
    </video>}
    <div className="hero-overlay" aria-hidden="true" />
    <div className="container hero-content">
      <div className="hero-copy">
        <p className="eyebrow light">DESIGN ENGINEERING / GLOBAL PROJECT SUPPORT</p>
        <h1>Engineering excellence.<br/>Delivered <em>worldwide.</em></h1>
        <p className="hero-description">Your trusted partner for design engineering, BIM & technical solutions. Precise, practical, and project-ready support, built around your business.</p>
        <div className="button-row"><a className="button primary" href="#services">Explore our services <Arrow/></a><a className="button outline-light" href="#contact">Discuss your project <Arrow/></a></div>
      </div>
      <aside className="hero-support glass"><span className="eyebrow light">YOUR EXTENDED ENGINEERING TEAM</span><p>From your first concept<br/>to your next deliverable.</p><a href="#delivery" className="text-link">Find your delivery model <Arrow/></a></aside>
    </div>
    <div className="container hero-bottom"><a href="#approach">Discover our approach <span aria-hidden="true">↓</span></a>
      {!reduced && !failed && <button className="video-toggle" onClick={toggle} aria-label={playing ? 'Pause background video' : 'Play background video'} aria-pressed={playing}><span aria-hidden="true">{playing ? 'Ⅱ' : '▷'}</span>{playing ? 'Pause video' : 'Play video'}</button>}
      {reduced && <span className="video-status">Static view · reduced motion</span>}{failed && <span className="video-status">Static view · video unavailable</span>}
    </div><p className="sr-only" role="status">{notice}</p>
  </section>
}
