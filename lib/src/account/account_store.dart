import 'dart:convert';

import 'package:cloud_tasks/src/account/nextcloud_account.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class AccountStore {
  Future<List<NextcloudAccount>> readAll();

  Future<void> save(NextcloudAccount account);

  Future<void> delete(String accountId);
}

class SecureAccountStore implements AccountStore {
  SecureAccountStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accountsKey = 'cloud_tasks.nextcloud_accounts.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<List<NextcloudAccount>> readAll() async {
    final encoded = await _storage.read(key: _accountsKey);
    if (encoded == null || encoded.isEmpty) {
      return const <NextcloudAccount>[];
    }

    final Object? decoded = jsonDecode(encoded);
    if (decoded is! List<Object?>) {
      throw const FormatException('Invalid saved account collection.');
    }

    return List<NextcloudAccount>.unmodifiable(
      decoded.map((item) {
        if (item is! Map<Object?, Object?>) {
          throw const FormatException('Invalid saved account entry.');
        }
        final values = <String, Object?>{};
        for (final entry in item.entries) {
          final key = entry.key;
          if (key is! String) {
            throw const FormatException('Invalid saved account entry.');
          }
          values[key] = entry.value;
        }
        return NextcloudAccount.fromJson(values);
      }),
    );
  }

  @override
  Future<void> save(NextcloudAccount account) async {
    final accounts = List<NextcloudAccount>.of(await readAll());
    final index = accounts.indexWhere((existing) => existing.id == account.id);
    if (index < 0) {
      accounts.add(account);
    } else {
      accounts[index] = account;
    }

    await _storage.write(
      key: _accountsKey,
      value: jsonEncode(accounts.map((item) => item.toJson()).toList()),
    );
  }

  @override
  Future<void> delete(String accountId) async {
    final accounts = List<NextcloudAccount>.of(await readAll())
      ..removeWhere((account) => account.id == accountId);
    if (accounts.isEmpty) {
      await _storage.delete(key: _accountsKey);
      return;
    }

    await _storage.write(
      key: _accountsKey,
      value: jsonEncode(accounts.map((item) => item.toJson()).toList()),
    );
  }
}
