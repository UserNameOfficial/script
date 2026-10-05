# Ragim Panel release instructions

When the user asks to update Ragim Panel, publish the tested `script.lua` to `UserNameOfficial/script` on `main`. Put one to three short, user-facing change lines in the commit body, each beginning `- `. The workflow in `.github/workflows/notify-discord.yml` then verifies the Raw script and posts the release to Discord. Confirm the workflow run succeeds before reporting the update complete. If it fails, fix the release workflow or Discord configuration and rerun it. Never add the Discord bot token to code, commit messages, terminal output, or logs.

Do not trigger an announcement for unrelated repository changes. The workflow runs automatically only when `script.lua` changes.
