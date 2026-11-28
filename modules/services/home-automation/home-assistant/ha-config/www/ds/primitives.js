import { sheet } from "./tokens.js?v=15";
export const primitives = sheet(`
.tile { background: var(--ha-card-background, var(--card-background-color)); border-radius: var(--ds-radius-tile);
  padding: var(--ds-tile-pad); box-shadow: var(--ha-card-box-shadow, none);
  border: var(--ha-card-border-width, 0) solid var(--ha-card-border-color, var(--divider-color));
  color: var(--primary-text-color); font: var(--ds-body); transition: background var(--ds-motion-state) var(--ds-ease); }
.tile--tint { background: color-mix(in srgb, var(--tint) 14%, var(--card-background-color)); }
.tile--tint .tile__title { color: color-mix(in srgb, var(--tint) 75%, var(--primary-text-color)); }
.tile__label { font: var(--ds-label); text-transform: uppercase; letter-spacing: .04em; color: var(--secondary-text-color); }
.tile__title { font: var(--ds-title); }
.tile__value { font: var(--ds-value); font-variant-numeric: tabular-nums; }
.tile__sub { color: var(--secondary-text-color); }
.chip { display: inline-flex; align-items: center; gap: 4px; min-height: 28px; padding: 4px 10px; border-radius: 999px;
  font: var(--ds-label); background: color-mix(in srgb, var(--secondary-text-color) 12%, var(--card-background-color)); color: var(--primary-text-color); }
.chip--tint { background: color-mix(in srgb, var(--tint) 14%, var(--card-background-color)); color: color-mix(in srgb, var(--tint) 75%, var(--primary-text-color)); }
.row { display: flex; justify-content: space-between; gap: var(--ds-space-3); padding: var(--ds-space-2) 0; border-top: 1px solid var(--divider-color); }
.row:first-child { border-top: 0; }
.row__k { color: var(--secondary-text-color); }
.row__v { font-weight: 600; font-variant-numeric: tabular-nums; }
.btn { min-height: var(--ds-touch); padding: 0 var(--ds-space-4); border-radius: 999px; border: 0; cursor: pointer;
  font: var(--ds-title); background: var(--primary-color); color: var(--text-primary-color); touch-action: manipulation; }
.btn:hover { filter: brightness(1.1); }
.btn:focus-visible, .chip:focus-visible, .tile:focus-visible { outline: 2px solid var(--primary-color); outline-offset: 2px; }
`);
