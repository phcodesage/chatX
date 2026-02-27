/// API Configuration
/// Change the baseUrl here to point to your backend server
class ApiConfig {
  // Base URL for the API - change this to switch backends
  static const String baseUrl = 'https://www.flask-call-app.site';
  //static const String baseUrl = 'https://m.flask-meet.site'; //production

  // API endpoints
  static const String authPrefix = '/api/auth';
  static const String mobilePrefix = '/api/mobile';

  // Auth endpoints
  static String get registerUrl => '$baseUrl$authPrefix/register';
  static String get loginUrl => '$baseUrl$authPrefix/login';
  static String get logoutUrl => '$baseUrl$authPrefix/logout';
  static String get meUrl => '$baseUrl$authPrefix/me';
  static String get forgotPasswordUrl => '$baseUrl$authPrefix/forgot-password';
  static String get resetPasswordUrl => '$baseUrl$authPrefix/reset-password';

  // Mobile endpoints
  static String get lobbyUrl => '$baseUrl$mobilePrefix/lobby';
  static String get usersUrl => '$baseUrl$mobilePrefix/users';
  static String get contactsUrl => '$baseUrl$mobilePrefix/contacts';
  static String get conversationsUrl =>
      '$baseUrl$mobilePrefix/messages/conversations';
  static String get sendMessageUrl => '$baseUrl$mobilePrefix/messages/send';
  static String get markReadUrl => '$baseUrl$mobilePrefix/messages/mark-read';
  static String get presenceStatusUrl =>
      '$baseUrl$mobilePrefix/presence/status';
  static String get heartbeatUrl => '$baseUrl$mobilePrefix/presence/heartbeat';

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // App update endpoints
  static String get appVersionUrl => '$baseUrl$mobilePrefix/app-version';
  static String get appDownloadUrl => '$baseUrl$mobilePrefix/app-download';

  // Task endpoints
  static String get tasksUrl => '$baseUrl$mobilePrefix/tasks';
  static String getTaskUrl(int taskId) => '$baseUrl$mobilePrefix/tasks/$taskId';
  static String getTaskCompleteUrl(int taskId) =>
      '$baseUrl$mobilePrefix/tasks/$taskId/complete';

  // Excalidraw endpoints
  static String get excalidrawBoardsUrl =>
      '$baseUrl$mobilePrefix/excalidraw/boards';
  static String getExcalidrawBoardUrl(String boardId) =>
      '$baseUrl$mobilePrefix/excalidraw/boards/$boardId';

  // Group endpoints
  static String get groupsUrl => '$baseUrl$mobilePrefix/groups';
  static String getGroupUrl(int groupId) =>
      '$baseUrl$mobilePrefix/groups/$groupId';
  static String getGroupMembersUrl(int groupId) =>
      '$baseUrl$mobilePrefix/groups/$groupId/members';
  static String getGroupMemberUrl(int groupId, int userId) =>
      '$baseUrl$mobilePrefix/groups/$groupId/members/$userId';
  static String getGroupLeaveUrl(int groupId) =>
      '$baseUrl$mobilePrefix/groups/$groupId/leave';
  static String getGroupMessagesUrl(int groupId) =>
      '$baseUrl$mobilePrefix/groups/$groupId/messages';
  static String getGroupMessageUrl(int groupId, int messageId) =>
      '$baseUrl$mobilePrefix/groups/$groupId/messages/$messageId';
  static String getGroupUploadUrl(int groupId) =>
      '$baseUrl$mobilePrefix/groups/$groupId/messages/upload';
  static String getGroupMessageDeliveredUrl(int groupId, int messageId) =>
      '$baseUrl$mobilePrefix/groups/$groupId/messages/$messageId/delivered';
  static String getGroupMessagesViewedUrl(int groupId) =>
      '$baseUrl$mobilePrefix/groups/$groupId/messages/viewed';
  static String getGroupMessageReactionsUrl(int groupId, int messageId) =>
      '$baseUrl$mobilePrefix/groups/$groupId/messages/$messageId/reactions';
  static String getGroupDoorbellUrl(int groupId) =>
      '$baseUrl$mobilePrefix/groups/$groupId/doorbell';
}
