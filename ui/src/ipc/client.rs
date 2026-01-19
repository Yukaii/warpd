use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;

use super::protocol::{Request, Response};

#[derive(Debug)]
pub struct IpcClient {
	socket_path: String,
	stream: Option<UnixStream>,
}

impl IpcClient {
	pub fn new(path: impl Into<String>) -> Self {
		Self {
			socket_path: path.into(),
			stream: None,
		}
	}

	pub fn connect(&mut self) -> io::Result<()> {
		let stream = UnixStream::connect(&self.socket_path)?;
		self.stream = Some(stream);
		Ok(())
	}

	pub fn request(&mut self, request: &Request) -> io::Result<Response> {
		let stream = self.stream.as_mut().ok_or_else(|| {
			io::Error::new(io::ErrorKind::NotConnected, "ipc not connected")
		})?;
		let mut payload = serde_json::to_vec(request)?;
		payload.push(b'\n');
		stream.write_all(&payload)?;

		let mut buf = Vec::new();
		let mut byte = [0u8; 1];
		loop {
			let n = stream.read(&mut byte)?;
			if n == 0 {
				break;
			}
			buf.push(byte[0]);
			if byte[0] == b'\n' {
				break;
			}
		}

		let response: Response = serde_json::from_slice(&buf)?;
		Ok(response)
	}
}
