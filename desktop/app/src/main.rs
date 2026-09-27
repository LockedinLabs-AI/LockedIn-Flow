#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod worker;

use lockedin_flow_core::vocabulary::MAX_INPUT;
use std::sync::{mpsc::SyncSender, Arc, Mutex};
use tauri::Manager;
use worker::{Action, Message, View};

struct Services {
    sender: SyncSender<Message>,
    view: Arc<Mutex<View>>,
}

fn own_window(window: &tauri::WebviewWindow) -> Result<(), &'static str> {
    if window.label() == "main" {
        Ok(())
    } else {
        Err("This window cannot control dictation.")
    }
}

#[tauri::command]
fn get_status(
    window: tauri::WebviewWindow,
    services: tauri::State<'_, Services>,
) -> Result<View, &'static str> {
    own_window(&window)?;
    services
        .view
        .lock()
        .map(|view| view.clone())
        .map_err(|_| "Dictation status is unavailable.")
}

#[tauri::command]
fn perform_action(
    window: tauri::WebviewWindow,
    services: tauri::State<'_, Services>,
    action: Action,
) -> Result<(), &'static str> {
    own_window(&window)?;
    {
        let view = services
            .view
            .lock()
            .map_err(|_| "Dictation status is unavailable.")?;
        if !action.allowed(view.phase) {
            return Err("This action is not available in the current dictation state.");
        }
    }
    services
        .sender
        .try_send(Message::Action(action))
        .map_err(|_| "LockedIn Flow is busy. Please wait for the current action.")
}

#[tauri::command]
fn set_vocabulary(
    window: tauri::WebviewWindow,
    services: tauri::State<'_, Services>,
    text: String,
) -> Result<(), &'static str> {
    own_window(&window)?;
    {
        let view = services
            .view
            .lock()
            .map_err(|_| "Dictation status is unavailable.")?;
        if view.phase != lockedin_flow_core::Phase::Ready {
            return Err("Finish the current recording before changing vocabulary.");
        }
    }
    if text.len() > MAX_INPUT {
        return Err("Vocabulary is limited to 16 KB.");
    }
    services
        .sender
        .try_send(Message::Vocabulary(zeroize::Zeroizing::new(text)))
        .map_err(|_| "LockedIn Flow is busy. Please wait for the current action.")
}

fn main() {
    let result = tauri::Builder::default()
        .setup(|app| {
            let resources = app.path().resource_dir()?;
            let (sender, view) = worker::spawn(resources)?;
            app.manage(Services { sender, view });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_status,
            perform_action,
            set_vocabulary
        ])
        .run(tauri::generate_context!());
    if result.is_err() {
        // Fixed, content-free failure. Never include transcript, device, or filesystem details.
        eprintln!("LockedIn Flow could not start its desktop interface.");
        std::process::exit(1);
    }
}
