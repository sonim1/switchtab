# Local Release Wrapper Design

## Goal

Create a one-command local release entry point:

```bash
./scripts/release-local.sh
```

The command loads stable, machine-specific release settings without requiring
manual `export` commands, then delegates the signed and notarized DMG build to
the existing `scripts/build-direct-distribution.sh --release` pipeline.

## Considered Approaches

1. **Ignored project-local environment file and wrapper (selected).** Keeps
   settings scoped to SwitchTab, works from any current directory, and leaves
   Apple credentials and the Sparkle private key in Keychain.
2. **Global shell profile exports.** Requires less repository code but leaks
   project-specific configuration into every shell and is easy to forget when
   moving to another Mac.
3. **Committed defaults in the distribution script.** Provides one command but
   hard-codes one developer's certificate identity into the public repository
   and makes forks harder to configure.

## Files and Responsibilities

### `.env.release.local`

An ignored, machine-local shell configuration file containing only:

- `SPARKLE_PUBLIC_ED_KEY`
- `DEVELOPER_ID_APPLICATION`
- `NOTARYTOOL_KEYCHAIN_PROFILE`

The Sparkle public key is not secret. The certificate display name and Keychain
profile label are identifiers, not credentials. Apple app-specific passwords,
Developer ID private keys, and the Sparkle private key must never be stored in
this file.

### `scripts/release-local.sh`

The wrapper will:

1. Resolve the repository root from its own location.
2. Require and source `$PROJECT_ROOT/.env.release.local`.
3. Validate the three required values are non-empty.
4. Execute the existing distribution script with `--release`.
5. Preserve quoted values such as the Developer ID certificate name.

The wrapper accepts no options. Advanced overrides remain available by running
`scripts/build-direct-distribution.sh` directly.

## Error Handling

- Missing `.env.release.local`: exit with a concise setup message.
- Missing required variable: identify the exact variable and exit before any
  build, signing, or notarization work begins.
- Build, signing, or notarization failure: preserve the delegated script's exit
  status and output.

## Testing

A shell contract test will copy the wrapper into a temporary project fixture
with a fake `build-direct-distribution.sh`. It will verify:

- a missing local configuration fails before delegation;
- a missing required value names that value and fails before delegation;
- a complete configuration forwards all values, including the certificate name
  with spaces, and exactly one `--release` argument;
- invocation works when the caller's current directory is outside the project;
- both scripts pass `bash -n` syntax validation.

The existing Swift test suite and direct-distribution `--prepare-only` check
remain the repository-wide regression gates. The real signed/notarized release
will not run as part of automated tests.
