# Contributing

Thanks for helping improve Coinscal. Bug reports, fixes, and translations are welcome.

## Before You Start

- Search [existing issues](https://github.com/gicek/coinscal/issues) first. For a bug, include your macOS version, Coinscal version, steps to reproduce, and what you expected.
- For a new feature or a change in scope, data sources, or architecture, open an issue to discuss it before writing code. The scope is defined in [Product](docs/PRODUCT.md); accounts, trading, charts, and key-based data sources are out of scope.

## Making a Change

1. Set up the toolchain and build with `make mac-run` ([Development](docs/DEVELOPMENT.md)).
2. Follow the repository rules in [AGENTS.md](AGENTS.md): architecture rules, localization, tests, and security.
3. Add tests at the lowest useful level, and add every new user-visible string in English, Simplified Chinese, and Traditional Chinese.
4. Update the documents your change affects, and add user-visible changes to the "Unreleased" section of [CHANGELOG](CHANGELOG.md).
5. Run `make test` and check that it ends with `** TEST SUCCEEDED **` and the website checks pass.

## Pull Requests

- Keep one change per pull request, with a clear description and screenshots for UI changes.
- Write commit messages as `<type>(<scope>): <summary>` in the imperative, for example `fix(alerts): reset reference price on currency change`.
- Don't commit build output, keys, or local configuration (`local.mk`).

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
