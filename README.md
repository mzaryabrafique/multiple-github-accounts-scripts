# Multiple GitHub Accounts

Two scripts that switch this machine between a **personal** GitHub account and an **other** GitHub account.

Each run updates git identity, HTTPS credentials, and (if installed) GitHub CLI auth so `git clone`, `git push`, and `git pull` use the selected profile.

## Scripts

| Script | Profile |
| --- | --- |
| `switch-personal.sh` | Personal GitHub account |
| `switch-other.sh` | Other GitHub account |

Shared logic lives in `lib/github-switch.sh`. Do not run that file directly.

## First-time setup

Create a [classic personal access token](https://github.com/settings/tokens) (`ghp_...`) for **each** account. Recommended scopes: `repo`, plus `workflow` and `gist` if you need them.

```bash
chmod +x switch-personal.sh switch-other.sh
./switch-personal.sh
./switch-other.sh
```

Each script asks for:

- Git commit name
- Git commit email
- GitHub username
- Classic PAT (input is hidden)

Credentials are saved under `~/.config/github-account-switcher/` with mode `600`. Tokens are never printed and are not stored in this repo.

## Daily use

```bash
./switch-personal.sh    # switch to personal
./switch-other.sh       # switch to other
```

After a switch, the script prints the active `user.name`, `user.email`, and `github.user`.

## Update a saved profile

```bash
./switch-personal.sh --setup
./switch-other.sh --setup
```

This re-prompts for name, email, username, and token, then switches to that profile.

## What a switch changes

- `git config --global user.name`
- `git config --global user.email`
- `git config --global github.user`
- GitHub HTTPS credentials for `github.com` and `gist.github.com` (macOS Keychain via `osxkeychain`, or `store` on Linux)
- `~/.netrc` entries for `github.com`, `gist.github.com`, and `api.github.com`
- `gh auth login` when the GitHub CLI is installed
- SSH remotes (`git@github.com:` and `ssh://git@github.com/`) rewritten to HTTPS so the PAT is used

To keep SSH remotes as SSH instead of rewriting them to HTTPS:

```bash
FORCE_GITHUB_HTTPS=0 ./switch-personal.sh
```

## Where credentials are stored

```
~/.config/github-account-switcher/
  personal.env    # personal name, email, username, token
  other.env       # other name, email, username, token
  active          # last profile switched to
```

This directory is `700`. Profile files are `600`. They are outside the repo on purpose.

## Requirements

- macOS or Linux
- `git`
- Interactive terminal for first-time setup
- A PAT starting with `ghp_` (classic) or `github_pat_` (fine-grained)

`gh` is optional. HTTPS + PAT is enough for clone, push, and pull.

## Security

- Do not commit tokens, `.env` files, or `~/.netrc`
- `.gitignore` already ignores `*.env` and `accounts/`
- Do not paste PATs into chat, issues, or pull requests
- Revoke a token on GitHub if it leaks, then re-run the matching script with `--setup`
