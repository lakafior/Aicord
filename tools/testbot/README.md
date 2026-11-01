# Aicord test bot

A bot for checking Aicord's interaction support by hand: slash commands with
every option type, autocomplete, subcommands, user and message commands,
v1 buttons and selects, a Components V2 message, modals, ephemeral, deferred
and edited replies, follow-ups. Commands are registered on one server only
(`NAScin`, or `AICORD_TEST_GUILD`), never globally.

Run it only for the length of a test, on your own computer, and stop it
afterwards (Ctrl+C).

## Setup

```bash
python3 -m venv /tmp/aicord-testbot-venv
/tmp/aicord-testbot-venv/bin/pip install "discord.py>=2.6"
```

## Run

The token is read at start-up and never printed. Either point the bot at a
file with a `Token` line followed by the token (default `~/Desktop/bot.txt`):

```bash
AICORD_BOT_FILE=~/Desktop/bot.txt /tmp/aicord-testbot-venv/bin/python tools/testbot/bot.py
```

or pass it in the environment for that one command (`DISCORD_BOT_TOKEN`).
Never put the token in the repository: `.env` and `bot.txt` are ignored.

If the bot is not on the server yet, it logs an invite link (scopes `bot
applications.commands`, View Channel and Send Messages only) and does nothing
else; open it yourself and approve.

## Commands

| Command | Tests |
|---|---|
| `/options` | string with choices, integer, number, boolean, user, channel, role, mentionable, attachment |
| `/fruit` | autocomplete |
| `/group alpha`, `/group beta`, `/group nested gamma` | subcommands and a subcommand group |
| Inspect user, Quote message | user and message context menu commands |
| `/buttons` | buttons in every style, link and disabled; update, ephemeral reply, thinking + follow-up, no reply, modal, deferred update |
| `/selects` | string (multi), user, role, mentionable and channel selects; each edits the message |
| `/v2` | Components V2: container, section with a button, separator, select, modal button |
| `/modal` | text inputs (action rows) and a select in a label |
| `/ephemeral`, `/defer`, `/edit`, `/silent` | ephemeral reply, thinking… then reply and follow-up, edited reply, no answer |
