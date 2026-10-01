import { useState } from 'react';

export function AccountAvatar({ name, url }: { name: string; url?: string }) {
  const [failedUrl, setFailedUrl] = useState<string>();
  let photo: string | undefined;
  try {
    if (typeof url === 'string' && new URL(url).protocol === 'https:') photo = url;
  } catch { /* Missing or invalid profile pictures use initials. */ }
  const initials = name.trim().split(/\s+/).map((part) => part[0]).join('').slice(0, 2).toUpperCase() || '?';
  return <span className="avatar">{photo && photo !== failedUrl
    ? <img src={photo} alt={`${name}'s Google profile photo`} referrerPolicy="no-referrer" onError={() => setFailedUrl(photo)} />
    : <span aria-hidden="true">{initials}</span>}</span>;
}
