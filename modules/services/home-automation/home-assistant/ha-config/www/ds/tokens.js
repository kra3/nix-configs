export const sheet = (css) => { const s = new CSSStyleSheet(); s.replaceSync(css); return s; };
export const tokens = sheet(`
:host {
  --ds-space-1: 4px; --ds-space-2: 8px; --ds-space-3: 12px; --ds-space-4: 16px; --ds-space-5: 24px;
  --ds-radius-tile: var(--ha-card-border-radius, 20px); --ds-radius-sheet: 24px;
  --ds-gap: 12px; --ds-tile-pad: 16px; --ds-touch: 44px;
  --ds-font: var(--ha-font-family-body, system-ui, sans-serif);
  --ds-label: 600 12px/1.3 var(--ds-font); --ds-body: 400 14px/1.4 var(--ds-font);
  --ds-title: 600 16px/1.3 var(--ds-font); --ds-value: 700 22px/1.2 var(--ds-font); --ds-hero: 700 32px/1.1 var(--ds-font);
  --ds-motion-state: 150ms; --ds-motion-sheet: 220ms; --ds-ease: cubic-bezier(.2,.8,.2,1);
}
@media (max-width: 819px) { :host { --ds-gap: 8px; } }
@media (prefers-reduced-motion: reduce) { :host { --ds-motion-state: 0ms; --ds-motion-sheet: 0ms; } }
`);
