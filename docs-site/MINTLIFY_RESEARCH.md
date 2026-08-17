# Mintlify workflow notes (internal)

Sources consulted:

- https://www.mintlify.com/docs
- https://www.mintlify.com/docs/quickstart
- https://www.mintlify.com/docs/organize/navigation
- https://www.mintlify.com/docs/cli
- https://www.mintlify.com/docs/organize/mintignore

Key findings:

- Mintlify uses a docs-as-code repository where pages are MDX files and `docs.json` controls navigation and site structure.
- The current configuration format uses a root `navigation` object with `groups`, where each group has a `group` label and a `pages` array.
- Mintlify’s CLI supports local preview with `mint dev`, validation with `mint validate`, broken-link checks with `mint broken-links`, accessibility checks with `mint a11y`, and formatting with `mint format`.
- The local preview is served at `http://localhost:3000` according to the official quickstart.
- `.mintignore` uses gitignore-style patterns and can exclude internal notes from publishing and search.
- The ZigMV site is therefore maintained as a separate `docs-site/` source tree, with internal research excluded from the published site.
