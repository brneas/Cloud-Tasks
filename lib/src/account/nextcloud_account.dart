class NextcloudAccount {
  const NextcloudAccount({
    required this.id,
    required this.serverUrl,
    required this.loginName,
    required this.appPassword,
  });

  final String id;
  final Uri serverUrl;
  final String loginName;
  final String appPassword;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'serverUrl': serverUrl.toString(),
      'loginName': loginName,
      'appPassword': appPassword,
    };
  }

  factory NextcloudAccount.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final serverUrl = json['serverUrl'];
    final loginName = json['loginName'];
    final appPassword = json['appPassword'];
    if (id is! String ||
        serverUrl is! String ||
        loginName is! String ||
        appPassword is! String) {
      throw const FormatException('Invalid saved Nextcloud account.');
    }

    return NextcloudAccount(
      id: id,
      serverUrl: Uri.parse(serverUrl),
      loginName: loginName,
      appPassword: appPassword,
    );
  }

  static String createId(Uri serverUrl, String loginName) {
    final path = serverUrl.path.replaceAll(RegExp(r'/+$'), '');
    return '${serverUrl.scheme}://${serverUrl.authority}$path|$loginName';
  }
}
