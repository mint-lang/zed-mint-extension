use zed_extension_api::{self as zed, settings::LspSettings, LanguageServerId, Result};

const SERVER_PATH: &str = "mint";
const SERVER_ARGS: [&str; 2] = ["tool", "ls"];

struct MintExtension;

impl MintExtension {
    fn language_server_binary(
        &self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<(String, Vec<String>)> {
        let binary = LspSettings::for_worktree(language_server_id.as_ref(), worktree)
            .ok()
            .and_then(|settings| settings.binary);

        let path = binary
            .as_ref()
            .and_then(|binary| binary.path.clone())
            .or_else(|| worktree.which(SERVER_PATH))
            .ok_or_else(|| {
                "mint is not installed, install it from https://mint-lang.com or set \
                 `lsp.mint.binary.path` in your settings"
                    .to_string()
            })?;

        let args = binary
            .and_then(|binary| binary.arguments)
            .unwrap_or_else(|| SERVER_ARGS.iter().map(ToString::to_string).collect());

        Ok((path, args))
    }
}

impl zed::Extension for MintExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        let (command, args) = self.language_server_binary(language_server_id, worktree)?;

        Ok(zed::Command {
            command,
            args,
            env: worktree.shell_env(),
        })
    }

    fn language_server_workspace_configuration(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<Option<zed::serde_json::Value>> {
        Ok(
            LspSettings::for_worktree(language_server_id.as_ref(), worktree)
                .ok()
                .and_then(|settings| settings.settings),
        )
    }
}

zed::register_extension!(MintExtension);
