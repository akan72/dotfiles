# Codex pets

Tumble's `pet.json` and `spritesheet.webp` are the complete runtime package,
including all animation frames and look directions. Generation prompts and
intermediate images are not required to restore the pet.

## Install on another machine

Running `./assimilate.sh` installs Tumble when it syncs Codex settings (requires
`yq` and `codex`). You can also run `./codex/sync-config.sh` directly. Both use
`${CODEX_HOME:-$HOME/.codex}/pets/tumble` and refresh the two packaged files on
each successful config sync, preserving other pets and additional local files.

For a manual install, run these commands from the root of this repository:

```sh
pet_dest="${CODEX_HOME:-$HOME/.codex}/pets/tumble"
mkdir -p "$pet_dest"
cp -i codex/pets/tumble/pet.json "$pet_dest/pet.json"
cp -i codex/pets/tumble/spritesheet.webp "$pet_dest/spritesheet.webp"
```

Restart Codex if needed, then select Tumble in the pet picker. Use a Codex
version that supports custom v2 pets. The selected pet preference is local to
the app and is not included in this package.
