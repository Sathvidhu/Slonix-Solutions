import { useEffect, useRef } from 'react'
export function Arrow() { return <span aria-hidden="true">↗</span> }
export function Wordmark() { return <span className="brand-lockup"><img src="/images/slonix-logo.png" alt="Slonix" width="72" height="72"/><span>SLONIX<small>SOLUTIONS</small></span></span> }
export function SectionHeading({label,title,text,children}) { return <div className="section-heading"><div><p className="eyebrow">{label}</p><h2>{title}</h2>{text && <p className="section-description">{text}</p>}</div>{children}</div> }
export function Modal({content,onClose}) {
 const ref=useRef(null)
 useEffect(()=>{const dialog=ref.current, previous=document.activeElement;dialog.showModal();const overflow=document.body.style.overflow;document.body.style.overflow='hidden';return()=>{dialog.close();document.body.style.overflow=overflow;previous?.focus()}},[])
 return <dialog ref={ref} aria-labelledby="modal-title" onCancel={e=>{e.preventDefault();onClose()}} onClick={e=>{if(e.target===ref.current)onClose()}}><div className="modal-content"><button className="close-button" onClick={onClose} aria-label="Close details">×</button><p className="eyebrow">{content.category}</p><h2 id="modal-title">{content.title}</h2><p>{content.body}</p><a className="button primary" href="#contact" onClick={onClose}>Discuss your project <Arrow/></a></div></dialog>
}
