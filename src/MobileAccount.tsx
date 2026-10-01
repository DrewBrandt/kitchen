import { useEffect, useId, useRef, useState } from 'react';
import { AccountAvatar } from './AccountAvatar';

export function MobileAccount({ name, email, photo, onProfile, onSignOut }: {
  name: string; email?: string; photo?: string; onProfile: () => void; onSignOut?: () => void;
}) {
  const [open, setOpen] = useState(false);
  const container = useRef<HTMLDivElement>(null);
  const toggle = useRef<HTMLButtonElement>(null);
  const panelId = useId();
  useEffect(() => {
    if (!open) return;
    const closeOutside = (event: PointerEvent) => {
      if (event.target instanceof Node && !container.current?.contains(event.target)) setOpen(false);
    };
    const closeWithEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { setOpen(false); toggle.current?.focus(); }
    };
    document.addEventListener('pointerdown', closeOutside);
    document.addEventListener('keydown', closeWithEscape);
    return () => {
      document.removeEventListener('pointerdown', closeOutside);
      document.removeEventListener('keydown', closeWithEscape);
    };
  }, [open]);
  return <div className="mobile-account" ref={container}>
    <button ref={toggle} className="mobile-account-toggle" aria-label={`Account: ${email || name}`} aria-expanded={open} aria-controls={panelId} onClick={() => setOpen(!open)}>
      <AccountAvatar name={name} url={photo} />
    </button>
    {open && <div id={panelId} className="mobile-account-panel" role="group" aria-label="Signed-in account">
      <small>Signed in as</small><strong>{name}</strong>{email && <span className="mobile-account-email">{email}</span>}
      <button onClick={() => { setOpen(false); onProfile(); }}>Routine &amp; food profile</button>
      {onSignOut && <button onClick={() => { setOpen(false); onSignOut(); }}>Sign out</button>}
    </div>}
  </div>;
}
