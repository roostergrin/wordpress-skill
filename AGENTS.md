# ACF WordPress Skills

This project manages ACF (Advanced Custom Fields) for a headless WordPress site. Four skills handle setup verification plus the full lifecycle: preflight, schema editing, deployment, and content management.
Use `skills/*.md` as the neutral source of truth and prefer the `wp-acf` wrapper for commands.

## When to use which skill

- **Building a page from a design/screenshot** — read `skills/workflow.md` first, then follow the skill chain.
- **Verifying setup and authentication before a demo or first run** — read `skills/wp-acf-preflight.md`.
- **Creating or modifying ACF field groups** — read `skills/acf-schema-edit.md`.
- **Deploying schema to WordPress** — read `skills/acf-schema-deploy.md`.
- **Reading or updating page/post content** — read `skills/wp-acf-content-api.md`.
- **Configuring paths for your environment** — read `skills/config.md`.
