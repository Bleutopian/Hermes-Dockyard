use serde::Serialize;
use std::{
    env,
    path::{Path, PathBuf},
    process::Command,
};

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct BackendProbe {
    action: String,
    available: bool,
    note: String,
    command: String,
    script_path: Option<String>,
    exit_code: Option<i32>,
    stdout: Option<String>,
    stderr: Option<String>,
}

#[tauri::command]
fn probe_backend_action(action: &str) -> BackendProbe {
    if !is_supported_backend_action(action) {
        return BackendProbe {
            action: action.to_string(),
            available: false,
            note: "Only allowlisted read-only actions are exposed in M2: preflight and status.".into(),
            command: String::new(),
            script_path: None,
            exit_code: None,
            stdout: None,
            stderr: None,
        };
    }

    let Some(script_path) = find_backend_script() else {
        return BackendProbe {
            action: action.to_string(),
            available: false,
            note: "Backend script not found. M2 wiring is present, but bundled read-only integration has not been configured yet.".into(),
            command: String::new(),
            script_path: None,
            exit_code: None,
            stdout: None,
            stderr: None,
        };
    };

    let mut command = Command::new("powershell");
    command.args([
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        script_path.to_string_lossy().as_ref(),
        action,
        "-OutputFormat",
        "json",
    ]);

    let command_preview = format!(
        "powershell -NoProfile -ExecutionPolicy Bypass -File \"{}\" {} -OutputFormat json",
        script_path.display(),
        action
    );

    match command.output() {
        Ok(output) => BackendProbe {
            action: action.to_string(),
            available: output.status.success(),
            note: if output.status.success() {
                "Read-only backend probe completed."
            } else {
                "Read-only backend probe returned a non-zero exit code. This is expected until the M1 JSON contract lands."
            }
            .into(),
            command: command_preview,
            script_path: Some(script_path.display().to_string()),
            exit_code: output.status.code(),
            stdout: string_or_none(&output.stdout),
            stderr: string_or_none(&output.stderr),
        },
        Err(error) => BackendProbe {
            action: action.to_string(),
            available: false,
            note: format!("Unable to launch the read-only backend probe: {error}"),
            command: command_preview,
            script_path: Some(script_path.display().to_string()),
            exit_code: None,
            stdout: None,
            stderr: None,
        },
    }
}

fn is_supported_backend_action(action: &str) -> bool {
    matches!(action, "preflight" | "status")
}

fn string_or_none(bytes: &[u8]) -> Option<String> {
    let value = String::from_utf8_lossy(bytes).trim().to_string();
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

fn find_backend_script() -> Option<PathBuf> {
    let candidates = [
        env::var("CARGO_MANIFEST_DIR").ok().map(PathBuf::from),
        env::current_dir().ok(),
        env::current_exe()
            .ok()
            .and_then(|path| path.parent().map(PathBuf::from)),
    ];

    candidates
        .into_iter()
        .flatten()
        .find_map(|start| find_in_ancestors(&start, Path::new("bin").join("agent-system.ps1")))
}

fn find_in_ancestors(start: &Path, needle: PathBuf) -> Option<PathBuf> {
    start
        .ancestors()
        .map(|path| path.join(&needle))
        .find(|candidate| candidate.exists())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![probe_backend_action])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::{find_backend_script, is_supported_backend_action};

    #[test]
    fn allowlist_is_read_only_and_fixed() {
        assert!(is_supported_backend_action("preflight"));
        assert!(is_supported_backend_action("status"));
        assert!(!is_supported_backend_action("update"));
        assert!(!is_supported_backend_action("uninstall"));
    }

    #[test]
    fn source_tree_probe_can_find_backend_script() {
        let script = find_backend_script().expect("expected to locate bin/agent-system.ps1");
        assert!(script.ends_with("bin\\agent-system.ps1") || script.ends_with("bin/agent-system.ps1"));
    }
}