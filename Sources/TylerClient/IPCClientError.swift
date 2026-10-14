package enum IPCClientError: Error, Equatable {
  case serverNotRunning(String)
  case badReply
}
