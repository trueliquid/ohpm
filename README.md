# ohpm

The Open Horizons Package Manager. Installs OpenComputers programs on OpenOS from public GitHub repos.

## Install

The computer needs an Internet card. In the shell:

```
wget -f https://raw.githubusercontent.com/trueliquid/ohpm/HEAD/install.lua /tmp/install.lua
/tmp/install.lua
```

## Using it

| Command | What it does |
|---|---|
| `ohpm install owner/repo` | Install a package and what it needs |
| `ohpm install owner/repo@ref` | Install from a branch, a tag or a full commit, and stay on it |
| `ohpm remove owner/repo` | Remove a package. Refused while another package needs it |
| `ohpm update [owner/repo]` | Update one package, or all of them |
| `ohpm list` | Show installed packages |
| `ohpm info owner/repo[@ref]` | Show a package, installed or not |
| `ohpm trust list` | Show trusted GitHub users |
| `ohpm trust add <user>` | Install from a user without asking |
| `ohpm trust remove <user>` | Ask again for a user |

Packages install under `/home`, so a program in `bin/` works as a command and a library in `lib/` works with `require`.

## Security

**ohpm does not check that code is safe to run.** Before installing from a GitHub user you have not trusted, it warns
you and asks, with these answers:

- `y` installs this once.
- `t` installs and trusts that user, so later installs and updates from them skip the question.
- `N`, or anything else, cancels.

Trust covers all of that user's repos and is not inherited: if a package you trust needs code from someone else, you are
still asked about them. Trust only means "accept what this account publishes". If an account is compromised, or a name
is given up and someone else registers it, ohpm installs from it without asking.

Downloads are checked for completeness by size, because SHA-256 needs a Data card. That catches a cut-off download, but
it does not prove where the content came from.

## Rate limits

GitHub limits anonymous requests per IP address, and every computer on a server shares the server's IP. Heavy use by
several players can cause temporary failures, especially on large packages, because each file is a separate request.
If ohpm reports a rate limit (HTTP 429), wait a while and try again.

ohpm does not use the GitHub API and its 60 requests an hour. GitHub publishes no limit for the endpoints it does use:

- `github.com/owner/repo.git/info/refs` finds the commit, one request per package.
- `raw.githubusercontent.com` downloads the manifest and each file.

## Making a package

Add a `package.cfg` to the root of a public repo and push it. No registration is needed.

```lua
{
    name = "example-package",
    version = "1.0.0",
    files = {
        ["example.lua"] = "lib/example.lua",
        ["cli/package.lua"] = "bin/package.lua"
    },
    dependencies = {"someone/cool-tool", "someone/cool-lib@v2"}
}
```

| Field | Meaning |
|---|---|
| `name` | Shown to the user. The package's identity is always `owner/repo` |
| `version` | Shown to the user. Updates are decided by commit, so ohpm never compares versions |
| `files` | Repo path on the left, target on the right, relative to `/home` |
| `dependencies` | Optional list of `owner/repo` or `owner/repo@ref` |

Targets cannot leave `/home` or start with a dot, which keeps packages away from `.shrc` and ohpm's own state. ohpm
refuses to overwrite a file that already exists or belongs to another package.

## Behaviour worth knowing

- Everything in a package comes from one commit, found before anything downloads, so a push during an install cannot
  mix versions.
- A package installed with `@ref` stays on that ref. `update` follows a branch, but a tag or commit stays put.
- If two packages need different versions of a dependency, ohpm stops. Only one version of a package can be installed.
- `remove` leaves dependencies behind, even if nothing needs them any more.
- A failed download changes nothing. Files only move into place after all of them have arrived. If that last step is
  interrupted, the next `ohpm` command finishes it from `/home/.ohpm/journal.cfg`.
- `package.cfg` is read with `serialization.unserialize`, which runs it as Lua with no access to the system, before the
  warning is shown.
- `finishConnect` also fails on HTTP errors, so the code comes from `response()`, which still works after that failure.

## State

| File | Holds |
|---|---|
| `/home/.ohpm/installed.cfg` | Installed packages, with their commits and files |
| `/home/.ohpm/trusted.cfg` | Trusted GitHub users |
| `/home/.ohpm/journal.cfg` | The install in progress, only while one is running |
| `/home/.ohpm/tmp/` | Downloads in progress |

## Code layout

| File | What it does |
|---|---|
| `bin/ohpm.lua` | The command line, and the only code that talks to the user |
| `lib/ohpm/init.lua` | The public API, what `require("ohpm")` loads |
| `lib/ohpm/manifest.lua` | Reads and checks package names and `package.cfg`, with no network or file access |
| `lib/ohpm/planner.lua` | Works out what to install: dependencies, version clashes and file conflicts |
| `lib/ohpm/transaction.lua` | Changes what is installed: the journal, installing, removing and crash recovery |
| `lib/ohpm/net.lua` | All network access, and no file access |
| `lib/ohpm/disk.lua` | All file access |
| `lib/ohpm/store.lua` | The installed list and the trust list |
| `install.lua` | The first install, run once and not installed itself |

`net` has three public functions: `findCommit`, `fetchManifest` and `downloadFile`. Another package source only has to
provide those.
