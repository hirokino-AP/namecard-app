// lib/services/firestore_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum CallResult { connected, absent, message }

extension CallResultExtension on CallResult {
  String get value {
    switch (this) {
      case CallResult.connected: return 'connected';
      case CallResult.absent:    return 'absent';
      case CallResult.message:   return 'message';
    }
  }
  String get label {
    switch (this) {
      case CallResult.connected: return '✅ 連絡取れた';
      case CallResult.absent:    return '📵 不在・折返し待ち';
      case CallResult.message:   return '💬 メッセージ送った';
    }
  }
}

class CallLog {
  final String result;
  final String memo;
  final String callerUid;
  final DateTime calledAt;

  const CallLog({required this.result, required this.memo,
      required this.callerUid, required this.calledAt});

  Map<String, dynamic> toMap() => {
    'result': result, 'memo': memo,
    'callerUid': callerUid, 'calledAt': calledAt.toIso8601String(),
  };
}

class FirestoreService {
  static final FirestoreService instance = FirestoreService._internal();
  FirestoreService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> addCallLog({required String todoId, required CallResult result,
      required String callerUid, String memo = ''}) async {
    try {
      final log = CallLog(result: result.value, memo: memo,
          callerUid: callerUid, calledAt: DateTime.now());
      await _firestore.collection('todos').doc(todoId).update({
        'callLogs': FieldValue.arrayUnion([log.toMap()]),
        'lastCallAt': log.calledAt.toIso8601String(),
        'lastCallResult': result.value,
      });
      return true;
    } catch (e) {
      debugPrint('Firestoreエラー: $e');
      return false;
    }
  }

  Future<bool> addTodoFromCard({required String userId, required String taskName,
      required String company, required String cardLocalId}) async {
    try {
      final now = DateTime.now();
      await _firestore.collection('todos').add({
        'task': taskName, 'company': company, 'cardLocalId': cardLocalId,
        'uid': userId, 'status': '進行中', 'callLogs': [],
        'createdAt': now.toIso8601String(), 'updatedAt': now.toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('Todo追加エラー: $e');
      return false;
    }
  }
}
