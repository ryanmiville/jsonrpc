//// JSON-RPC is a stateless, light-weight remote procedure call (RPC) protocol.
//// Primarily this specification defines several data structures and the rules
//// around their processing. It is transport agnostic in that the concepts can be
//// used within the same process, over sockets, over http, or in many various
//// message passing environments. It uses JSON (RFC 4627) as data format.
////
//// The error codes from and including -32768 to -32000 are reserved for
//// pre-defined errors. Any code within this range, but not defined explicitly below
//// is reserved for future use.
////
//// | code | message | meaning |
//// | --- | --- | --- |
//// | -32700 | Parse error | Invalid JSON was received by the server. An error occurred on the server while parsing the JSON text. |
//// | -32600 | Invalid Request | The JSON sent is not a valid Request object. |
//// | -32601 | Method not found | The method does not exist / is not available. |
//// | -32602 | Invalid params | Invalid method parameter(s). |
//// | -32603 | Internal error | Internal JSON-RPC error. |
//// | -32000 to -32099 | Server error | Reserved for implementation-defined server-errors. |
////
//// The remainder of the space is available for application defined errors.

import gleam/dynamic/decode.{type Decoder, type Dynamic}
import gleam/function
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

/// A union of the JSON-RPC message types.
pub type Message {
  RequestMessage(Request(Dynamic))
  NotificationMessage(Notification(Dynamic))
  ResponseMessage(Response(Dynamic))
  ErrorResponseMessage(ErrorResponse(Dynamic))
  BatchRequestMessage(BatchRequest(Dynamic))
  BatchResponseMessage(BatchResponse(Dynamic))
}

pub fn message_decoder() -> Decoder(Message) {
  let request = request_decoder(decode.dynamic) |> decode.map(RequestMessage)
  let notification =
    notification_decoder(decode.dynamic) |> decode.map(NotificationMessage)
  let response = response_decoder(decode.dynamic) |> decode.map(ResponseMessage)
  let error_response =
    error_response_decoder(decode.dynamic) |> decode.map(ErrorResponseMessage)
  let batch_request = batch_request_decoder() |> decode.map(BatchRequestMessage)
  let batch_response =
    batch_response_decoder() |> decode.map(BatchResponseMessage)

  decode.one_of(request, [
    notification,
    response,
    error_response,
    batch_request,
    batch_response,
  ])
}

/// A request that is made up of a list of JSON-RPC requests and/or notifications.
/// Items in a batch request MUST be able to be processed in any other. As such,
/// order is not preserved.
pub opaque type BatchRequest(a) {
  BatchRequest(List(BatchRequestItem(a)))
}

/// retrieve the list of BatchRequestItems
pub fn batch_request_items(
  batch_request: BatchRequest(a),
) -> List(BatchRequestItem(a)) {
  let BatchRequest(batch) = batch_request
  batch
}

/// Create a new, empty batch request
pub fn batch_request() -> BatchRequest(Json) {
  BatchRequest([])
}

pub fn batch_request_to_json(batch_request: BatchRequest(Json)) -> Json {
  let BatchRequest(batch) = batch_request
  json.array(batch, batch_request_item_to_json)
}

pub fn batch_request_decoder() -> Decoder(BatchRequest(Dynamic)) {
  decode.list(batch_request_item_decoder()) |> decode.map(BatchRequest)
}

/// Add a request to a batch request. Batch requests have no guarantees about
/// order. Therefore order is not preserved when your batch request is sent.
pub fn add_request(
  batch_request: BatchRequest(Json),
  request: Request(a),
  params_to_json: fn(a) -> Json,
) -> BatchRequest(Json) {
  let BatchRequest(batch) = batch_request
  let request =
    Request(..request, params: option.map(request.params, params_to_json))
    |> BatchRequestItemRequest
  BatchRequest([request, ..batch])
}

/// Add a notification to a batch request. Batch requests have no guarantees about
/// order. Therefore order is not preserved when your batch request is sent.
pub fn add_notification(
  batch_request: BatchRequest(Json),
  notification: Notification(a),
  params_to_json: fn(a) -> Json,
) -> BatchRequest(Json) {
  let BatchRequest(batch) = batch_request
  let notification =
    Notification(
      ..notification,
      params: option.map(notification.params, params_to_json),
    )
    |> BatchRequestItemNotification

  BatchRequest([notification, ..batch])
}

/// A union of the types allowed in a single batch request.
pub type BatchRequestItem(a) {
  BatchRequestItemRequest(Request(a))
  BatchRequestItemNotification(Notification(a))
}

pub fn batch_request_item_decoder() -> Decoder(BatchRequestItem(Dynamic)) {
  let request =
    request_decoder(decode.dynamic) |> decode.map(BatchRequestItemRequest)
  let notification =
    notification_decoder(decode.dynamic)
    |> decode.map(BatchRequestItemNotification)

  decode.one_of(request, [notification])
}

pub fn batch_request_item_to_json(item: BatchRequestItem(Json)) {
  case item {
    BatchRequestItemRequest(msg) -> request_to_json(msg, function.identity)
    BatchRequestItemNotification(msg) ->
      notification_to_json(msg, function.identity)
  }
}

/// A response that is made up of a list of JSON-RPC responses and/or error responses.
/// A batch response should contain a response or error response for each
/// request in the request batch (except for notifications).
/// Items in a batch response are not ordered. The client is responsible to map
/// the response IDs to their own request IDs.
pub opaque type BatchResponse(a) {
  BatchResponse(List(BatchResponseItem(a)))
}

/// retrieve the list of BatchResponseItems
pub fn batch_response_items(batch_response: BatchResponse(a)) {
  let BatchResponse(batch) = batch_response
  batch
}

/// Create a new, empty batch response
pub fn batch_response() -> BatchResponse(Json) {
  BatchResponse([])
}

pub fn batch_response_decoder() -> Decoder(BatchResponse(Dynamic)) {
  decode.list(batch_response_item_decoder()) |> decode.map(BatchResponse)
}

pub fn batch_response_to_json(batch_response: BatchResponse(Json)) {
  let BatchResponse(batch) = batch_response
  json.array(batch, batch_response_item_to_json)
}

/// Add a response to a batch response. Batch responses have no guarantees about
/// order. Therefore order is not preserved when your batch response is sent.
pub fn add_response(
  batch_response: BatchResponse(Json),
  response: Response(a),
  result_to_json: fn(a) -> Json,
) -> BatchResponse(Json) {
  let BatchResponse(batch) = batch_response
  let response =
    Response(..response, result: result_to_json(response.result))
    |> BatchResponseItemResponse
  BatchResponse([response, ..batch])
}

/// Add an error response to a batch response. Batch responses have no guarantees about
/// order. Therefore order is not preserved when your batch response is sent.
pub fn add_error_response(
  batch_response: BatchResponse(Json),
  error_response: ErrorResponse(a),
  data_to_json: fn(a) -> Json,
) -> BatchResponse(Json) {
  let BatchResponse(batch) = batch_response
  let error =
    ErrorBody(
      ..error_response.error,
      data: option.map(error_response.error.data, data_to_json),
    )
  let error_response =
    ErrorResponse(..error_response, error:)
    |> BatchResponseItemErrorResponse
  BatchResponse([error_response, ..batch])
}

/// A union of the types allowed in a single batch response.
pub type BatchResponseItem(a) {
  BatchResponseItemResponse(Response(a))
  BatchResponseItemErrorResponse(ErrorResponse(a))
}

pub fn batch_response_item_to_json(item: BatchResponseItem(Json)) {
  case item {
    BatchResponseItemErrorResponse(msg) ->
      error_response_to_json(msg, function.identity)
    BatchResponseItemResponse(msg) -> response_to_json(msg, function.identity)
  }
}

pub fn batch_response_item_decoder() -> Decoder(BatchResponseItem(Dynamic)) {
  let response =
    response_decoder(decode.dynamic) |> decode.map(BatchResponseItemResponse)
  let error_response =
    error_response_decoder(decode.dynamic)
    |> decode.map(BatchResponseItemErrorResponse)

  decode.one_of(response, [error_response])
}

/// Specifies the version of the JSON-RPC protocol. Only 2.0 is supported.
pub type Version {
  V2
}

pub fn version_to_json(_version: Version) -> Json {
  json.string("2.0")
}

pub fn version_decoder() -> Decoder(Version) {
  use v <- decode.then(decode.string)
  case v {
    "2.0" -> decode.success(V2)
    _ -> decode.failure(V2, "unsupported JSON-RPC version: " <> v)
  }
}

/// An identifier established by the Client that MUST contain a String, Number,
/// or NULL value. The value SHOULD normally not be Null.
pub type Id {
  StringId(String)
  IntId(Int)
  NullId
}

/// Creates an Int ID
pub fn id(id: Int) -> Id {
  IntId(id)
}

pub fn id_to_json(id: Id) -> Json {
  case id {
    IntId(id) -> json.int(id)
    NullId -> json.null()
    StringId(id) -> json.string(id)
  }
}

pub fn id_decoder() -> Decoder(Id) {
  let string_decoder = decode.string |> decode.map(StringId)
  let others =
    decode.optional(decode.int |> decode.map(IntId))
    |> decode.map(option.unwrap(_, NullId))

  decode.one_of(string_decoder, [others])
}

/// An RPC call to a server
pub type Request(params) {
  Request(
    /// Specifies the version of the JSON-RPC protocol. MUST be exactly "2.0".
    jsonrpc: Version,
    /// A String containing the name of the method to be invoked. Method names
    /// that begin with the word rpc followed by a period character (U+002E or
    /// ASCII 46) are reserved for rpc-internal methods and extensions and MUST
    /// NOT be used for anything else.
    method: String,
    /// An identifier established by the Client that MUST contain a String, Number,
    /// or NULL value. The value SHOULD normally not be Null.
    id: Id,
    /// A Structured value that holds the parameter values to be used during the
    /// invocation of the method. This member MAY be omitted.
    params: Option(params),
  )
}

/// Creates a new request with empty params
pub fn request(method method: String, id id: Id) -> Request(params) {
  Request(jsonrpc: V2, method:, id:, params: None)
}

/// Sets the params of this request
pub fn request_params(request: Request(a), params: params) -> Request(params) {
  Request(..request, params: Some(params))
}

pub fn request_to_json(
  request: Request(params),
  encode_params: fn(params) -> Json,
) -> Json {
  let Request(jsonrpc:, method:, id:, params:) = request
  let params = case params {
    Some(params) -> [#("params", encode_params(params))]
    None -> []
  }
  json.object([
    #("jsonrpc", version_to_json(jsonrpc)),
    #("method", json.string(method)),
    #("id", id_to_json(id)),
    ..params
  ])
}

pub fn request_decoder(
  params_decoder: Decoder(params),
) -> Decoder(Request(params)) {
  use jsonrpc <- decode.field("jsonrpc", version_decoder())
  use method <- decode.field("method", decode.string)
  use id <- decode.field("id", id_decoder())
  use params <- decode.optional_field(
    "params",
    None,
    decode.optional(params_decoder),
  )
  decode.success(Request(jsonrpc:, method:, id:, params:))
}

/// A type that can help with type inference for RPC objects that omit optional
/// fields.
pub opaque type Nothing {
  Nothing
}

/// Encode json for the Nothing type, which is impossible to create. This
/// is intended for fields you KNOW are omitted, and therefore it will never be
/// ran. It will always return `null` if ran.
pub fn nothing_to_json(_nothing: Nothing) -> Json {
  json.null()
}

/// A decoder for the Nothing type, which is impossible to create. This decoder
/// is intended for fields you KNOW are omitted, and therefore it will never be
/// ran. It will always fail if ran
pub fn nothing_decoder() -> Decoder(Nothing) {
  decode.failure(Nothing, "Attempted to decode a Nothing type.")
}

/// A notification signifies the Client's lack of interest in the corresponding
/// Response object, and as such no Response object needs to be returned to the
/// client. The Server MUST NOT reply to a Notification, including those that
/// are within a batch request.
///
/// Notifications are not confirmable by definition, since they do not have a
/// Response object to be returned. As such, the Client would not be aware of
/// any errors (like e.g. "Invalid params","Internal error").
pub type Notification(params) {
  Notification(
    /// Specifies the version of the JSON-RPC protocol. MUST be exactly "2.0".
    jsonrpc: Version,
    /// A String containing the name of the method to be invoked. Method names
    /// that begin with the word rpc followed by a period character (U+002E or
    /// ASCII 46) are reserved for rpc-internal methods and extensions and MUST
    /// NOT be used for anything else.
    method: String,
    /// A Structured value that holds the parameter values to be used during the
    /// invocation of the method. This member MAY be omitted.
    params: Option(params),
  )
}

/// Creates a new notification with empty params
pub fn notification(method: String) -> Notification(params) {
  Notification(jsonrpc: V2, method:, params: None)
}

/// Sets the params for this notification
pub fn notification_params(
  notification: Notification(a),
  params: params,
) -> Notification(params) {
  Notification(..notification, params: Some(params))
}

pub fn notification_to_json(
  notification: Notification(params),
  encode_params: fn(params) -> Json,
) -> Json {
  let Notification(jsonrpc:, method:, params:) = notification
  let params = case params {
    Some(params) -> [#("params", encode_params(params))]
    None -> []
  }

  json.object([
    #("jsonrpc", version_to_json(jsonrpc)),
    #("method", json.string(method)),
    ..params
  ])
}

pub fn notification_decoder(
  params_decoder: Decoder(params),
) -> Decoder(Notification(params)) {
  use jsonrpc <- decode.field("jsonrpc", version_decoder())
  use method <- decode.field("method", decode.string)
  use params <- decode.optional_field(
    "params",
    None,
    decode.optional(params_decoder),
  )
  decode.success(Notification(jsonrpc:, method:, params:))
}

/// When an RPC call is made, the Server MUST reply with a Response, except for
/// in the case of Notifications.
pub type Response(result) {
  Response(
    /// Specifies the version of the JSON-RPC protocol. MUST be exactly "2.0".
    jsonrpc: Version,
    /// It MUST be the same as the value of the id member in the Request Object.
    id: Id,
    /// The value of this member is determined by the method invoked on the
    /// Server.
    result: result,
  )
}

/// Creates a new response
pub fn response(result result: result, id id: Id) -> Response(result) {
  Response(jsonrpc: V2, id:, result:)
}

pub fn response_to_json(
  response: Response(result),
  encode_result: fn(result) -> Json,
) -> Json {
  let Response(jsonrpc:, id:, result:) = response
  json.object([
    #("jsonrpc", version_to_json(jsonrpc)),
    #("id", id_to_json(id)),
    #("result", encode_result(result)),
  ])
}

pub fn response_decoder(
  result_decoder: Decoder(result),
) -> Decoder(Response(result)) {
  use jsonrpc <- decode.field("jsonrpc", version_decoder())
  use id <- decode.field("id", id_decoder())
  use result <- decode.field("result", result_decoder)
  decode.success(Response(jsonrpc:, id:, result:))
}

/// When an RPC call encounters an error, the server MUST send an error
/// response, except in the case of Notifications.
pub type ErrorResponse(data) {
  ErrorResponse(
    /// Specifies the version of the JSON-RPC protocol. MUST be exactly "2.0".
    jsonrpc: Version,
    /// It MUST be the same as the value of the id member in the Request Object.
    /// If there was an error in detecting the id in the Request object (e.g.
    /// Parse error/Invalid Request), it MUST be Null.
    id: Id,
    /// When a rpc call encounters an error, the Response Object MUST contain
    /// the error member with a value that is a Object with the following
    /// members:
    error: ErrorBody(data),
  )
}

/// Creates a new error response with empty data. Error code and message are
/// populated with the values from `error`.
pub fn error_response(
  error error: JsonRpcError,
  id id: Id,
) -> ErrorResponse(data) {
  ErrorResponse(
    jsonrpc: V2,
    id:,
    error: ErrorBody(code: error.code, message: error.message, data: None),
  )
}

/// Sets the data of this error response
pub fn error_response_data(
  error_response: ErrorResponse(a),
  data: data,
) -> ErrorResponse(data) {
  let error = ErrorBody(..error_response.error, data: Some(data))
  ErrorResponse(..error_response, error:)
}

pub fn error_response_to_json(
  error_response: ErrorResponse(data),
  encode_data: fn(data) -> Json,
) -> Json {
  let ErrorResponse(jsonrpc:, id:, error:) = error_response
  json.object([
    #("jsonrpc", version_to_json(jsonrpc)),
    #("id", id_to_json(id)),
    #("error", error_to_json(error, encode_data)),
  ])
}

pub fn error_response_decoder(
  data_decoder: Decoder(data),
) -> Decoder(ErrorResponse(data)) {
  use jsonrpc <- decode.field("jsonrpc", version_decoder())
  use id <- decode.field("id", id_decoder())
  use error <- decode.field("error", error_decoder(data_decoder))
  decode.success(ErrorResponse(jsonrpc:, id:, error:))
}

/// When an RPC call encounters an error, the Response Object MUST contain the
/// error member
pub type ErrorBody(data) {
  ErrorBody(
    /// A Number that indicates the error type that occurred.
    code: Int,
    /// A String providing a short description of the error.
    /// The message SHOULD be limited to a concise single sentence.
    message: String,
    /// A Primitive or Structured value that contains additional information
    /// about the error.
    /// This may be omitted.
    /// The value of this member is defined by the Server (e.g. detailed error
    /// information, nested errors etc.).
    data: Option(data),
  )
}

pub fn error_to_json(
  error: ErrorBody(data),
  encode_data: fn(data) -> Json,
) -> Json {
  let ErrorBody(code:, message:, data:) = error
  let data = case data {
    Some(data) -> [#("data", encode_data(data))]
    None -> []
  }
  json.object([
    #("code", json.int(code)),
    #("message", json.string(message)),
    ..data
  ])
}

pub fn error_decoder(data_decoder: Decoder(data)) -> Decoder(ErrorBody(data)) {
  use code <- decode.field("code", decode.int)
  use message <- decode.field("message", decode.string)
  use data <- decode.optional_field("data", None, decode.optional(data_decoder))
  decode.success(ErrorBody(code:, message:, data:))
}

pub fn error_response_from(
  json_error: json.DecodeError,
  id: Id,
) -> ErrorResponse(Nothing) {
  case json_error {
    json.UnableToDecode(errors) -> from_decode_errors(errors, id)
    _ -> error_response(parse_error, id)
  }
}

fn from_decode_errors(errors: List(decode.DecodeError), id: Id) {
  let params_error =
    list.all(errors, fn(error) { list.first(error.path) == Ok("params") })

  case params_error {
    True -> error_response(invalid_params, id)
    False -> error_response(invalid_request, id)
  }
}

// ERRORS ----------------------------------------------------------------------

/// Invalid JSON was received by the server. An error occurred on the server
/// while parsing the JSON text.
pub const parse_error = JsonRpcError(-32_700, "Parse error")

/// The JSON sent is not a valid Request object.
pub const invalid_request = JsonRpcError(-32_600, "Invalid Request")

/// The method does not exist / is not available.
pub const method_not_found = JsonRpcError(-32_601, "Method not found")

/// Invalid method parameter(s).
pub const invalid_params = JsonRpcError(-32_602, "Invalid params")

/// Internal JSON-RPC error.
pub const internal_error = JsonRpcError(-32_603, "Internal error")

/// Represents the error code and associated message. Error types provided by the JSON-RPC spec are already defined in the module.
pub opaque type JsonRpcError {
  JsonRpcError(code: Int, message: String)
}

/// Retrieve this error's code
pub fn error_code(error: JsonRpcError) {
  error.code
}

/// Retrieve this error's message
pub fn error_message(error: JsonRpcError) {
  error.message
}

/// An error defined for your specific application.
/// The error code MUST not be within the range -32768 to -32000, otherwise
/// `Error(Nil)` will be returned.
/// The message SHOULD be limited to a concise single sentence.
pub fn application_error(
  code: Int,
  message: String,
) -> Result(JsonRpcError, Nil) {
  case code >= -32_768 && code <= -32_000 {
    True -> Error(Nil)
    False -> Ok(JsonRpcError(code, message))
  }
}

/// An error reserved for implementation-defined server-errors.
/// The error code MUST be within the range -32099 to -32000, otherwise
/// `Error(Nil)` will be returned.
pub fn server_error(code: Int) -> Result(JsonRpcError, Nil) {
  case code >= -32_099 && code <= -32_000 {
    True -> Ok(JsonRpcError(code, "Server error"))
    False -> Error(Nil)
  }
}

/// Get the appropriate `JsonRpcError` based on a request's `json.DecodeError`.
pub fn json_error(error: json.DecodeError) -> JsonRpcError {
  case error {
    json.UnableToDecode(errors) -> decode_errors(errors)
    _ -> parse_error
  }
}

/// Get the appropriate `JsonRpcError` based on a request's `decode.DecodeError`s.
pub fn decode_errors(errors: List(decode.DecodeError)) -> JsonRpcError {
  case list.all(errors, param_error) {
    True -> invalid_params
    False -> invalid_request
  }
}

fn param_error(error: decode.DecodeError) {
  list.first(error.path) == Ok("params")
}
