use gpui::{
	prelude::*, App, Application, Bounds, Context, SharedString, Window, WindowBounds,
	WindowOptions, div, px, rgb, size, Stateful,
};
use serde_json::Value;

use crate::ipc::client::IpcClient;
use crate::ipc::protocol::Request;

#[derive(Clone)]
struct ElementItem {
	id: u64,
	hint: SharedString,
	label: SharedString,
	role: SharedString,
	desc: SharedString,
}

impl ElementItem {
	fn display_line(&self) -> SharedString {
		if self.label.is_empty() {
			let fallback = if self.desc.is_empty() {
				self.role.as_ref()
			} else {
				self.desc.as_ref()
			};
			format!("[{}] {}", self.hint, fallback).into()
		} else {
			format!("[{}] {} ({})", self.hint, self.label, self.role).into()
		}
	}
}

struct WarpdUi {
	title: SharedString,
	status: SharedString,
	socket_path: SharedString,
	elements: Vec<ElementItem>,
}

impl Render for WarpdUi {
	fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
		div()
			.flex()
			.flex_col()
			.gap_3()
			.size(px(360.0))
			.justify_center()
			.items_center()
			.bg(rgb(0x1f1f1f))
			.text_color(rgb(0xffffff))
			.text_xl()
			.child(self.title.clone())
			.child(self.status.clone())
			.child(
				div()
					.flex()
					.flex_none()
					.gap_2()
					.child(
						ui_button("Refresh")
							.on_click(cx.listener(|this, _, _, cx| {
								let socket = this.socket_path.clone();
								this.refresh_elements(&socket);
								cx.notify();
							})),
					),
			)
			.child(
				div()
					.flex()
					.flex_col()
					.gap_1()
					.text_sm()
					.children(self.elements.iter().map(|item| {
						let id = item.id;
						let line = item.display_line();
						div()
							.id(SharedString::from(format!("element-{}", id)))
							.flex()
							.flex_none()
							.px_2()
							.py_1()
							.rounded_sm()
							.bg(rgb(0x2a2a2a))
							.cursor_pointer()
							.child(line)
							.on_click(cx.listener(move |this, _, _, cx| {
								let socket = this.socket_path.clone();
								this.send_element_action(&socket, id, "elements.click");
								cx.notify();
							}))
					})),
			)
	}
}

fn ui_button(text: &str) -> Stateful<gpui::Div> {
	div()
		.id(SharedString::from(format!("button-{}", text)))
		.flex_none()
		.px_2()
		.py_1()
		.bg(rgb(0x3a3a3a))
		.border_1()
		.border_color(rgb(0x4a4a4a))
		.rounded_sm()
		.cursor_pointer()
		.child(text.to_string())
}

fn parse_elements(result: &Value) -> Vec<ElementItem> {
	let mut elements = Vec::new();
	let items = match result.get("elements").and_then(|v| v.as_array()) {
		Some(items) => items,
		None => return elements,
	};

	for item in items.iter().take(50) {
		let id = item.get("id").and_then(|v| v.as_u64()).unwrap_or(0);
		let hint = item.get("hint").and_then(|v| v.as_str()).unwrap_or("");
		let label = item.get("label").and_then(|v| v.as_str()).unwrap_or("");
		let role = item.get("role").and_then(|v| v.as_str()).unwrap_or("");
		let desc = item.get("desc").and_then(|v| v.as_str()).unwrap_or("");
		elements.push(ElementItem {
			id,
			hint: hint.to_string().into(),
			label: label.to_string().into(),
			role: role.to_string().into(),
			desc: desc.to_string().into(),
		});
	}

	elements
}

fn ipc_request(socket_path: &str, request: &Request) -> Option<Value> {
	let mut client = IpcClient::new(socket_path);
	if client.connect().is_err() {
		return None;
	}
	client.request(request).ok().and_then(|resp| resp.result)
}

impl WarpdUi {
	fn refresh_elements(&mut self, socket_path: &str) {
		let request = Request {
			id: 2,
			method: "elements.list".to_string(),
			params: None,
		};
		if let Some(result) = ipc_request(socket_path, &request) {
			self.elements = parse_elements(&result);
			self.status = "elements refreshed".into();
		} else {
			self.status = "elements refresh failed".into();
		}
	}

	fn send_element_action(&mut self, socket_path: &str, id: u64, method: &str) {
		let request = Request {
			id: 3,
			method: method.to_string(),
			params: Some(serde_json::json!({ "id": id })),
		};
		if ipc_request(socket_path, &request).is_some() {
			self.status = format!("sent {}", method).into();
		} else {
			self.status = format!("{} failed", method).into();
		}
	}
}

pub fn run() {
	Application::new().run(|cx: &mut App| {
		let mut ipc_status = "IPC: disconnected".to_string();
		let socket_path: SharedString = "/tmp/warpd.sock".into();
		let mut elements: Vec<ElementItem> = Vec::new();

		let status_request = Request {
			id: 1,
			method: "status".to_string(),
			params: None,
		};
		if let Some(result) = ipc_request(&socket_path, &status_request) {
			if let Some(version) = result.get("version").and_then(|v| v.as_str()) {
				ipc_status = format!("daemon: {}", version);
			} else {
				ipc_status = "IPC: connected".to_string();
			}
		}

		let elements_request = Request {
			id: 2,
			method: "elements.list".to_string(),
			params: None,
		};
		if let Some(result) = ipc_request(&socket_path, &elements_request) {
			elements = parse_elements(&result);
		}

		let bounds = Bounds::centered(None, size(px(640.0), px(360.0)), cx);
		cx.open_window(
			WindowOptions {
				window_bounds: Some(WindowBounds::Windowed(bounds)),
				..Default::default()
			},
			|_, cx| cx.new(|_| WarpdUi {
				title: "warpd ui".into(),
				status: ipc_status.into(),
				socket_path,
				elements,
			}),
		)
		.unwrap();
		cx.activate(true);
	});
}
