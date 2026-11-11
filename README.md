# Claude Usage — KDE Plasma 6 widget

[Русская версия](README.ru.md)

Two rings in a Plasma panel that show how much of your Claude Pro subscription limits you have already used:

- **left ring**: the 5-hour window;
- **right ring**: the weekly limit.

The percentage is shown inside each ring. The widget is meant to be read at a glance: no clicking, no expanding, no settings.

```
   ╭───╮ ╭───╮
   │ 25│ │ 10│      5 hours: 25%, resets in 1 h 40 min
   ╰───╯ ╰───╯      Week: 10%, resets in 4 d 21 h        ← tooltip on hover
```

(The tooltip text in the actual widget is in Russian; see [Limitations](#limitations).)

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [How it works](#how-it-works)
- [Privacy and security](#privacy-and-security)
- [Limitations](#limitations)
- [What has and has not been verified](#what-has-and-has-not-been-verified)
- [Development](#development)
- [What the widget intentionally does not do](#what-the-widget-intentionally-does-not-do)
- [License](#license)

## Requirements

- KDE Plasma 6 (developed and tested on Plasma 6.8.2, KDE neon).
- `curl` and `jq`.
- [Claude Code](https://claude.com/claude-code) signed in with a subscription. The widget takes the OAuth token from `~/.claude/.credentials.json`. If the file is missing, the widget shows gray rings with a dash.

## Installation

From the repository root:

```bash
kpackagetool6 --type Plasma/Applet --install claude-usage
```

Then: right-click the panel → **Add Widgets** → **Claude Usage**. If the widget is not in the list, restart the shell:

```bash
plasmashell --replace &
```

Updating after code changes:

```bash
kpackagetool6 --type Plasma/Applet --upgrade claude-usage
plasmashell --replace &      # widgets already on a panel will not pick up new code without a restart
```

Removal:

```bash
kpackagetool6 --type Plasma/Applet --remove local.claude-usage
```

The widget ID is `local.claude-usage`, while the directory in the repository is called `claude-usage`. `--install` and `--upgrade` take the directory, `--remove` takes the ID.

## Usage

There is nothing to configure. The widget is universal: it works in horizontal and vertical panels as well as on the desktop.

### Ring color

The color comes from the system theme, so it follows light and dark themes.

| Usage | Ring color |
|---|---|
| below 80% | theme accent color |
| 80% and above | orange (warning) |
| 95% and above | red |
| no data, or data is stale | gray |

The 80% and 95% thresholds are hardcoded and not configurable.

### Tooltip

Hovering shows the percentage and the time until reset for each limit. The time left is calculated when you hover, not on every poll.

If the last request failed, a line "Данные устарели, последнее обновление: HH:MM" ("Data is stale, last update: HH:MM") is added. If there has never been any data, the tooltip says "Не удалось получить данные. Войдите в Claude Code." ("Could not get data. Sign in to Claude Code.").

### Layout

- Horizontal panel: rings in a row, ring diameter equals the available panel thickness.
- Vertical panel: rings stacked one above the other.
- Desktop: layout depends on the widget's proportions; rings fit the available area.

Ring diameter is limited by the panel thickness minus the panel's own inner padding. On a 30 px panel the rings come out at about 22 px, on a 46 px panel at about 30 px. If the rings look too small, make the panel thicker.

## How it works

Every 10 minutes (and immediately on startup) the widget runs:

```bash
jq -r '"Authorization: Bearer " + .claudeAiOauth.accessToken' "$HOME/.claude/.credentials.json" | \
  curl -sS --max-time 15 -H @- -H 'anthropic-beta: oauth-2025-04-20' \
       -w '\n%{http_code}' https://api.anthropic.com/api/oauth/usage
```

The command is run through the `executable` engine of `Plasma5Support`. Two blocks of the response are used:

| Response field | What it shows |
|---|---|
| `five_hour.utilization`, `five_hour.resets_at` | 5-hour window: percentage and reset time |
| `seven_day.utilization`, `seven_day.resets_at` | weekly limit: percentage and reset time |

All other fields of the response (per-model Sonnet and Opus limits and so on) are ignored.

A response counts as successful if the HTTP code is 200, the body parses as JSON, and it contains a `seven_day` block. If the `five_hour` block is missing, it is treated as an inactive window and 0% is shown. This is an assumption: a real response without this block has not been observed.

### What happens on errors

On any error (no network, expired token, non-200 code, unexpected format) the rings turn gray and keep the last known values. The next attempt is in 10 minutes.

The widget does **not** refresh the token itself. Claude Code refreshes it, so if you have not run Claude Code for a long time the token may expire and the widget stays gray until the next Claude Code run. Refreshing the token from the widget is intentionally not implemented: the token may be single-use, and doing so could break your Claude Code sign-in.

## Privacy and security

- The token is read from a local file at request time. The widget does not store or log it anywhere.
- The token is passed to `curl` through stdin (`-H @-`), so it is not visible in the process list.
- The token is sent only to `api.anthropic.com`.
- The widget makes no other external requests.
- The repository contains no tokens, and `.gitignore` covers credential files, raw API responses, logs and screenshots.

## Limitations

- **The endpoint is unofficial.** The `/api/oauth/usage` address and the `anthropic-beta: oauth-2025-04-20` header are not documented anywhere. Anthropic may change or remove them without notice, after which the widget will stop getting data. Several third-party tools use it, but there are no guarantees.
- **Request rate.** The API answers more frequent requests with 429, hence the 10-minute interval. The interval is hardcoded (`interval: 600000` in `main.qml`).
- **Subscription only.** It requires a Claude Code sign-in with a subscription, not an API key. The widget has only been tested with Pro.
- **Russian UI text.** The tooltip is written in Russian; there is no localization.
- **Stale after a reset.** Between a limit resetting and the next poll, the ring still shows the old value, and the tooltip says "сброс наступил" ("reset has occurred").

## What has and has not been verified

Verified:

- a request to the endpoint with a real token: HTTP 200, the response format matches the description;
- operation in horizontal Plasma panels of 30 and 46 px and in a test `plasmawindowed` window;
- color change at 86% (orange) and 97% (red) and the gray error state: on fake data in a test window;
- ring and digit sizes in real panels, checked from screenshots.

Not verified:

- **vertical panel**: the code is there, but nobody has seen the layout on screen;
- **tooltip** on hover: the text is written, but it has not been looked at in a panel;
- **a value of 100%**: a three-digit number should shrink automatically, but it has not been seen in practice;
- **color change on real data**: only on fake data;
- an API response without the `five_hour` block.

## Development

Structure:

```
claude-usage/
├── metadata.json          # Plasma package description
└── contents/ui/main.qml   # all of the widget code
```

All the code is a single QML file:

- a `PlasmoidItem` with `preferredRepresentation: fullRepresentation`: the rings are shown right in the panel, without a popup;
- a `Plasma5Support.DataSource` with the `executable` engine: runs the command every 10 minutes and parses the response;
- a `Ring` component: a ring built on `QtQuick.Shapes` with a number inside;
- a `GridLayout`: layout depending on the panel form factor.

Without adding it to a panel, you can check the widget in a separate window:

```bash
plasmawindowed local.claude-usage
```

This shows the desktop layout and QML errors in the console, but not the behavior in a panel. Ring size in a panel depends on the thickness the panel allots: it is derived from the size of the widget's root item, not from the size of the layout itself, otherwise the rings get stuck at the minimum size.

To check colors and the error state without the real API, temporarily put into the `command` property in `main.qml` a command that prints fake JSON followed by a line `200` (or `echo oops` to simulate an error), and run `plasmawindowed`. Do not forget to restore the original command.

## What the widget intentionally does not do

These are deliberate decisions, not unfinished work:

- settings for colors and polling interval: thresholds change the color on their own, and colors come from the theme;
- limits for individual models (Sonnet, Opus);
- notifications when approaching a limit;
- API key support;
- token refresh;
- click to force a refresh.

## License

MIT, see [LICENSE](LICENSE).
