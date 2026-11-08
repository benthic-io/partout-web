# partout-web

The PartOut website: a single-page Hugo site for <https://partout.pro>.

PartOut is a crowd-sourced parts-matching and public-data project. The app is
under development.

## Build

Requires Hugo extended 0.169.0.

```bash
hugo --minify
```

The build writes `public/`. `scripts/build_site.sh` does the same and clears
stale output first.

## Structure

- `content/` — page content
- `layouts/` — templates
- `static/` — CSS, images, `robots.txt`
- `hugo.toml` — site configuration

## License

No license file exists yet. The public-data license is **pending** counsel
review; do not describe the code or data as MIT, open source, open data, or
public domain until that changes.

Contact: [brian@benthic.io](mailto:brian@benthic.io)
