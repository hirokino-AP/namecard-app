// ============================================================
// lib/interfaces/i_external_app.dart
//
// 【役割】
//   外部アプリ連携のインターフェース。
//   TodoアプリやFutureアプリはこのIFを実装する。
//
// 【設計原則】
//   連携先アプリには個人情報を渡さない。
//   contact_id（識別子）のみを渡し、deep linkで名刺詳細に飛ぶ。
//   個人情報は名刺アプリが一元管理する。
// ============================================================

abstract class IExternalApp {
  // contact_idのみで連携（個人情報は含まない）
  Future<void> linkContact(String contactId);

  // deep linkを生成（個人情報は含まない）
  String generateDeepLink(String contactId);

  // 連携先アプリ名
  String get appName;
}
