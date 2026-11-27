# PR 8 Health report

Branch ha-bento/08-health. Files: views/health-arun.yaml, views/health-anjali.yaml (type custom:command-centre, max_columns 3, `!include ../rail.yaml` first, Heart split into its own section so desktop shows 3 columns). Mapping: pr8-health-mapping.md.

## Checks
- nix fmt: 0 changed. ha-lint build: ok. sutala toplevel build: ok.
- Dashboard load (container Python): 11/11 views; only idx 2,3 (health-arun/anjali) differ from base; streamline templates identical; visible identical; non-rail cards identical (17 each, same order).
- Harness not run: no card code changed.

## Rulings
- health-metric-card not retrofitted to ds classes (optional per brief, "where it doesn't change options"; no version bump, keeps PR 2's cc_detail behaviour).
- Split Heart into a third section for the 3-column layout rather than reordering content.

## Requests for foundation
none
