use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct Request {
	pub id: u64,
	pub method: String,
	pub params: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Response {
	pub id: u64,
	pub result: Option<serde_json::Value>,
	pub error: Option<RpcError>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Notification {
	pub method: String,
	pub params: Option<serde_json::Value>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RpcError {
	pub code: i32,
	pub message: String,
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn request_roundtrip() {
		let request = Request {
			id: 1,
			method: "status".to_string(),
			params: Some(serde_json::json!({ "verbose": true })),
		};
		let json = serde_json::to_string(&request).expect("serialize");
		let parsed: Request = serde_json::from_str(&json).expect("deserialize");
		assert_eq!(parsed.id, 1);
		assert_eq!(parsed.method, "status");
		assert_eq!(parsed.params, request.params);
	}

	#[test]
	fn response_roundtrip() {
		let response = Response {
			id: 2,
			result: Some(serde_json::json!({ "ok": true })),
			error: None,
		};
		let json = serde_json::to_string(&response).expect("serialize");
		let parsed: Response = serde_json::from_str(&json).expect("deserialize");
		assert_eq!(parsed.id, 2);
		assert_eq!(parsed.result, response.result);
		assert!(parsed.error.is_none());
	}
}
