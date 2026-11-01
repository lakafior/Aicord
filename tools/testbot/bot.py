"""Aicord's interaction test bot.

Registers guild commands on one server only (NAScin by default) and answers
them with every kind of response Aicord has to handle. Run it locally, only
for the length of a test. See README.md.

The token is read when the bot starts, from DISCORD_BOT_TOKEN or from the file
in AICORD_BOT_FILE (default ~/Desktop/bot.txt). It is never printed or logged.
"""

import asyncio
import logging
import os
import pathlib
import sys

import discord
from discord import app_commands, ui

GUILD_NAME = os.environ.get("AICORD_TEST_GUILD", "NAScin")
log = logging.getLogger("testbot")


def read_token() -> str:
    token = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    if token:
        return token
    path = pathlib.Path(os.environ.get("AICORD_BOT_FILE", "~/Desktop/bot.txt")).expanduser()
    lines = [line.strip() for line in path.read_text().splitlines()]
    # the line after a "Token" label, or anything shaped like a bot token
    for index, line in enumerate(lines):
        if line.lower().startswith("token") and index + 1 < len(lines):
            label_value = line.split(":", 1)[1].strip() if ":" in line else ""
            return label_value or lines[index + 1]
    for line in lines:
        if line.count(".") == 2 and len(line) > 50:
            return line
    sys.exit("No bot token found: set DISCORD_BOT_TOKEN or add a Token line to the file.")


intents = discord.Intents.none()
intents.guilds = True
# replies name people and roles without pinging them
client = discord.Client(intents=intents, allowed_mentions=discord.AllowedMentions.none())
tree = app_commands.CommandTree(client)


# MARK: - Slash commands with every option type


@tree.command(name="options", description="Every option type; echoes what arrived")
@app_commands.describe(
    text="String with choices",
    count="Integer 1-100",
    ratio="Number",
    flag="Boolean",
    who="User",
    where="Channel",
    role="Role",
    target="Mentionable",
    file="Attachment",
)
@app_commands.choices(
    text=[
        app_commands.Choice(name="Apple", value="apple"),
        app_commands.Choice(name="Banana", value="banana"),
        app_commands.Choice(name="Cherry", value="cherry"),
    ]
)
async def options(
    interaction: discord.Interaction,
    text: app_commands.Choice[str],
    count: app_commands.Range[int, 1, 100] | None = None,
    ratio: float | None = None,
    flag: bool | None = None,
    who: discord.User | None = None,
    where: discord.abc.GuildChannel | None = None,
    role: discord.Role | None = None,
    target: discord.Role | discord.User | None = None,
    file: discord.Attachment | None = None,
):
    lines = [
        f"text: **{text.name}** (`{text.value}`)",
        f"count: {count}",
        f"ratio: {ratio}",
        f"flag: {flag}",
        f"who: {who.mention if who else None}",
        f"where: {where.mention if where else None}",
        f"role: {role.name if role else None}",
        f"target: {getattr(target, 'name', None)}",
        f"file: {f'{file.filename} ({file.size} B)' if file else None}",
    ]
    await interaction.response.send_message("\n".join(lines), ephemeral=True)


FRUITS = ["Apple", "Apricot", "Avocado", "Banana", "Blueberry", "Cherry", "Grape", "Kiwi", "Lemon",
          "Mango", "Orange", "Peach", "Pear", "Plum", "Raspberry", "Strawberry"]


async def fruit_autocomplete(interaction: discord.Interaction, current: str):
    return [app_commands.Choice(name=f, value=f.lower()) for f in FRUITS
            if current.lower() in f.lower()][:25]


@tree.command(name="fruit", description="Autocomplete")
@app_commands.autocomplete(name=fruit_autocomplete)
async def fruit(interaction: discord.Interaction, name: str):
    await interaction.response.send_message(f"You picked **{name}**.", ephemeral=True)


group = app_commands.Group(name="group", description="Subcommands")
nested = app_commands.Group(name="nested", description="A subcommand group", parent=group)


@group.command(name="alpha", description="Subcommand alpha")
async def group_alpha(interaction: discord.Interaction, note: str | None = None):
    await interaction.response.send_message(f"/group alpha, note: {note}", ephemeral=True)


@group.command(name="beta", description="Subcommand beta")
async def group_beta(interaction: discord.Interaction, number: int):
    await interaction.response.send_message(f"/group beta, number: {number}", ephemeral=True)


@nested.command(name="gamma", description="Subcommand in a group")
async def nested_gamma(interaction: discord.Interaction, flag: bool):
    await interaction.response.send_message(f"/group nested gamma, flag: {flag}", ephemeral=True)


tree.add_command(group)


# MARK: - Context menu commands


@tree.context_menu(name="Inspect user")
async def inspect_user(interaction: discord.Interaction, user: discord.User):
    await interaction.response.send_message(
        f"{user.name} ({user.id}), bot: {user.bot}", ephemeral=True)


@tree.context_menu(name="Quote message")
async def quote_message(interaction: discord.Interaction, message: discord.Message):
    text = message.content or "(no text)"
    await interaction.response.send_message(f"> {text[:300]}\n— {message.author.name}")


# MARK: - Responses


class Feedback(ui.Modal, title="Aicord feedback"):
    name = ui.TextInput(label="Name", placeholder="Your name", max_length=50)
    details = ui.TextInput(label="Details", style=discord.TextStyle.paragraph, required=False,
                           max_length=500)
    mood = ui.Label(
        text="Mood", description="A select inside a modal",
        component=ui.Select(options=[discord.SelectOption(label=m) for m in ["Good", "Fine", "Bad"]]))

    async def on_submit(self, interaction: discord.Interaction):
        mood = self.mood.component.values if isinstance(self.mood.component, ui.Select) else []
        await interaction.response.send_message(
            f"Modal: name **{self.name.value}**, details: {self.details.value or '—'}, "
            f"mood: {', '.join(mood) or '—'}", ephemeral=True)


class Buttons(ui.View):
    def __init__(self):
        super().__init__(timeout=None)
        self.count = 0
        self.add_item(ui.Button(label="Link", style=discord.ButtonStyle.link,
                                url="https://github.com/lakafior/Aicord"))
        self.add_item(ui.Button(label="Disabled", style=discord.ButtonStyle.secondary, disabled=True,
                                custom_id="disabled"))

    @ui.button(label="Update (primary)", style=discord.ButtonStyle.primary, emoji="🔁")
    async def update(self, interaction: discord.Interaction, _):
        self.count += 1
        await interaction.response.edit_message(content=f"Buttons, clicked {self.count}×", view=self)

    @ui.button(label="Ephemeral (secondary)", style=discord.ButtonStyle.secondary)
    async def ephemeral(self, interaction: discord.Interaction, _):
        await interaction.response.send_message("Only you can see this reply.", ephemeral=True)

    @ui.button(label="Think (success)", style=discord.ButtonStyle.success)
    async def think(self, interaction: discord.Interaction, _):
        await interaction.response.defer(thinking=True)
        await asyncio.sleep(4)
        await interaction.followup.send("Done thinking (follow-up after defer).")

    @ui.button(label="No reply (danger)", style=discord.ButtonStyle.danger)
    async def silent(self, interaction: discord.Interaction, _):
        pass  # never answers, so Discord fails the interaction after 3 s

    @ui.button(label="Modal", style=discord.ButtonStyle.primary, row=1)
    async def modal(self, interaction: discord.Interaction, _):
        await interaction.response.send_modal(Feedback())

    @ui.button(label="Defer update", style=discord.ButtonStyle.secondary, row=1)
    async def defer_update(self, interaction: discord.Interaction, _):
        await interaction.response.defer()
        await asyncio.sleep(2)
        await interaction.edit_original_response(content="Edited after a deferred update.", view=self)


@tree.command(name="buttons", description="v1 buttons in every style")
async def buttons(interaction: discord.Interaction):
    await interaction.response.send_message("Buttons, clicked 0×", view=Buttons())


def describe(values) -> str:
    return ", ".join(getattr(v, "mention", None) or getattr(v, "name", None) or str(v)
                     for v in values) or "—"


class Selects(ui.View):
    def __init__(self):
        super().__init__(timeout=None)

    async def show(self, interaction: discord.Interaction, kind: str, values):
        await interaction.response.edit_message(content=f"{kind}: {describe(values)}", view=self)

    @ui.select(placeholder="String select (pick 1-2)", min_values=1, max_values=2, options=[
        discord.SelectOption(label="Red", value="red", emoji="🔴", description="Warm"),
        discord.SelectOption(label="Green", value="green", emoji="🟢"),
        discord.SelectOption(label="Blue", value="blue", emoji="🔵", default=True),
    ])
    async def strings(self, interaction: discord.Interaction, select: ui.Select):
        await self.show(interaction, "String", select.values)

    @ui.select(cls=ui.UserSelect, placeholder="User select")
    async def users(self, interaction: discord.Interaction, select: ui.UserSelect):
        await self.show(interaction, "User", select.values)

    @ui.select(cls=ui.RoleSelect, placeholder="Role select")
    async def roles(self, interaction: discord.Interaction, select: ui.RoleSelect):
        await self.show(interaction, "Role", select.values)

    @ui.select(cls=ui.MentionableSelect, placeholder="Mentionable select", max_values=3)
    async def mentionables(self, interaction: discord.Interaction, select: ui.MentionableSelect):
        await self.show(interaction, "Mentionable", select.values)

    @ui.select(cls=ui.ChannelSelect, placeholder="Text channel select",
               channel_types=[discord.ChannelType.text])
    async def channels(self, interaction: discord.Interaction, select: ui.ChannelSelect):
        await self.show(interaction, "Channel", select.values)


@tree.command(name="selects", description="String, user, role, mentionable and channel selects")
async def selects(interaction: discord.Interaction):
    await interaction.response.send_message("Pick something.", view=Selects())


class V2(ui.LayoutView):
    def __init__(self):
        super().__init__(timeout=None)
        self.count = 0
        self.status = ui.TextDisplay("Clicks: 0")
        bump = ui.Button(label="Bump", style=discord.ButtonStyle.primary)
        bump.callback = self.bump
        pick = ui.Select(placeholder="Pick a size", options=[
            discord.SelectOption(label=s, value=s.lower()) for s in ["Small", "Medium", "Large"]])
        pick.callback = self.pick
        self.pick_select = pick
        modal = ui.Button(label="Open modal", style=discord.ButtonStyle.secondary)
        modal.callback = self.modal
        self.add_item(ui.Container(
            ui.TextDisplay("## Components V2\nA container with a section, buttons and a select."),
            ui.Section(ui.TextDisplay("Section text with a button accessory."), accessory=bump),
            ui.Separator(),
            self.status,
            ui.ActionRow(pick),
            ui.ActionRow(modal, ui.Button(label="Docs", url="https://docs.discord.food")),
            accent_colour=discord.Colour.blurple(),
        ))

    async def bump(self, interaction: discord.Interaction):
        self.count += 1
        self.status.content = f"Clicks: {self.count}"
        await interaction.response.edit_message(view=self)

    async def pick(self, interaction: discord.Interaction):
        self.status.content = f"Size: {', '.join(self.pick_select.values)}"
        await interaction.response.edit_message(view=self)

    async def modal(self, interaction: discord.Interaction):
        await interaction.response.send_modal(Feedback())


@tree.command(name="v2", description="A Components V2 message with buttons and a select")
async def v2(interaction: discord.Interaction):
    await interaction.response.send_message(view=V2())


@tree.command(name="modal", description="Opens a modal")
async def modal(interaction: discord.Interaction):
    await interaction.response.send_modal(Feedback())


@tree.command(name="ephemeral", description="An ephemeral reply")
async def ephemeral(interaction: discord.Interaction):
    await interaction.response.send_message("Only you can see this.", ephemeral=True,
                                            view=Buttons())


@tree.command(name="defer", description="Thinking…, then a reply and a follow-up")
async def defer(interaction: discord.Interaction):
    await interaction.response.defer(thinking=True)
    await asyncio.sleep(4)
    await interaction.followup.send("Reply after thinking.")
    await asyncio.sleep(1)
    await interaction.followup.send("A follow-up message.", ephemeral=True)


@tree.command(name="edit", description="A reply that edits itself")
async def edit(interaction: discord.Interaction):
    await interaction.response.send_message("Original reply…")
    await asyncio.sleep(2)
    await interaction.edit_original_response(content="Edited reply.")


@tree.command(name="silent", description="Never answers")
async def silent(interaction: discord.Interaction):
    pass


async def sync(guild: discord.Guild):
    tree.copy_global_to(guild=guild)
    synced = await tree.sync(guild=guild)
    log.info("Synced %d commands on %s (%s)", len(synced), guild.name, guild.id)


@client.event
async def on_guild_join(guild: discord.Guild):
    if guild.name == GUILD_NAME:
        await sync(guild)


@client.event
async def on_ready():
    guild = discord.utils.get(client.guilds, name=GUILD_NAME)
    if guild is None:
        log.warning("Bot is not on %s. Servers: %s", GUILD_NAME, [g.name for g in client.guilds])
        app = await client.application_info()
        perms = discord.Permissions(send_messages=True, view_channel=True)
        log.warning("Invite: %s", discord.utils.oauth_url(
            app.id, permissions=perms, scopes=("bot", "applications.commands")))
        return
    await sync(guild)


if __name__ == "__main__":
    discord.utils.setup_logging(level=logging.INFO)
    client.run(read_token(), log_handler=None)
