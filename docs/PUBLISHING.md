# Releasing Carta on GitHub

## Work with the source repository

Clone the repository to start a new working copy.

```sh
git clone https://github.com/theo79-ita/carta.git
cd carta
```

Run the tests and build the app from the repository root. The build script includes Carta's MIT license and its third-party notices in the application bundle. The app bundle and ZIP are generated under `dist/`. [Build and test guide](DEVELOPMENT.md) · [Third-party notices](../THIRD_PARTY_NOTICES.md)

## Release version 0.3.0

For a source release, run the tests, verify the version in `scripts/Info.plist`, and tag the commit you want users to download:

```sh
git tag -a v0.3.0 -m "Carta 0.3.0"
git push origin v0.3.0
```

On the repository page, open **Releases → Draft a new release**, select the existing tag `v0.3.0` and enter **Carta 0.3.0** as the title. Describe the changes and list the macOS 13+ requirement and the English and Italian interface languages. GitHub provides source archives from the tag. A source release can be published on its own. The packaged app is always named `Carta.app`. [GitHub release documentation](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)

### Optional Mac app download

The build script uses an ad hoc signature for local testing. To offer a download that opens through the normal macOS Gatekeeper flow, build the intended architecture, sign the app with a Developer ID Application certificate and hardened runtime, and submit the signed product with Apple's notary service. After acceptance, staple the ticket to the app, validate it, and create a **fresh ZIP containing the stapled app**. The earlier ad hoc ZIP predates those steps. [Apple's signing guide](https://developer.apple.com/developer-id/) · [Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Attach the final ZIP to the GitHub release. State its architecture (for example, Apple silicon/arm64) and macOS deployment target. Keep the downloadable ZIP under **Releases** so the Git history stays focused on source changes.
