# Zed Mint Extension

Language support for the [Mint programming language](https://mint-lang.com):
syntax highlighting (Tree-sitter) and language server support.

## Language server

The extension uses the language server built into the Mint compiler
(`mint tool ls`), so no separate installation is needed - `mint` just has to be
on your `PATH`.

If you want to point Zed at a different binary or pass different arguments, add
this to your Zed settings:

```json
{
  "lsp": {
    "mint": {
      "binary": {
        "path": "/path/to/mint",
        "arguments": ["tool", "ls"]
      }
    }
  }
}
```

## Development

The extension's WASM component is built inside a container, so no local Rust
toolchain is required - only Docker:

```bash
./build.sh
```

The build happens entirely inside the container: the cargo registry and target
directory live in Docker's build cache, and the only thing written to the
working tree is `extension.wasm`, which is what Zed loads.

Zed does not notice the change on its own: the extension is registered as a
symlinked dev extension, so Zed's file watcher never sees writes inside it.

- After a change to `extension.toml`, force an index rescan - restarting Zed is
  not enough, it reuses the cached index in
  `~/.local/share/zed/extensions/index.json`:

  ```bash
  touch ~/.local/share/zed/extensions/installed/.rescan
  rm ~/.local/share/zed/extensions/installed/.rescan
  ```

  Zed logs `rebuilt extension index` followed by `extensions updated`.

- After a change to `extension.wasm` alone, restart Zed. The rescan above only
  reloads extensions whose manifest changed, but `extension.wasm` is read from
  disk every time an extension is loaded.

> [!IMPORTANT]
> `zed: install dev extension` and `zed: rebuild dev extension` compile the
> extension with a local Rust toolchain, so they fail without one. Use
> `./build.sh` + a restart instead; the extension only has to be registered as
> a dev extension once.
