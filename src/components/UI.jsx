import { useEffect, useRef } from 'react'
export function Arrow() { return <span aria-hidden="true">&#8599;</span> }
export function Wordmark() { return <span className="wordmark">slonix<span className="brand-dot">.</span><small>SOLUTIONS</small></span> }
export function SectionHeading({ label, title, text, children }) { return <div className="section-heading"><div><p className="eyebrow">{label}</p><h2>{title}</h2>{text && <p className="section-description">{text}</p>}</div>{children}</div> }
export function Modal({ content, onClose }) {
  const ref = useRef(null)
  useEffect(() => {
    const dialog = ref.current
    const previous = document.activeElement
    dialog.showModal()
    const overflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { dialog.close(); document.body.style.overflow = overflow; previous?.focus() }
  }, [])
  return <dialog ref={ref} aria-labelledby="modal-title" onCancel={e => { e.preventDefault(); onClose() }} onClick={e => { if(e.target === ref.current) onClose() }}><div className="modal-content"><button className="close-button" onClick={onClose} aria-label="Close details">×</button><p className="eyebrow">{content.category || 'SAMPLE INSIGHT'}</p><h2 id="modal-title">{content.title}</h2><p>{content.description || content.body}</p>{content.topics && <><h3>Topics to explore</h3><ul>{content.topics.map(t => <li key={t}>{t}</li>)}</ul><p className="small-note">Indicative overview for this prototype. Confirm the current syllabus, prerequisites, format, fees, and duration with Slonix.</p></>}<a className="button primary" href="#contact" onClick={onClose}>Discuss your learning goals <Arrow /></a></div></dialog>
}
