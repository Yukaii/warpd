#[derive(Debug, Clone)]
pub struct IpcClient {
	socket_path: String,
}

impl IpcClient {
	pub fn new(path: impl Into<String>) -> Self {
		Self {
			socket_path: path.into(),
		}
	}

	pub fn socket_path(&self) -> &str {
		&self.socket_path
	}
}
