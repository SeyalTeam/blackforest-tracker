import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class TrackerCallHistoryEntry {
  final String eventKey;
  final String callId;
  final String customerName;
  final String? callerRole;
  final String? callerUserId;
  final String? receiverUserId;
  final String status;
  final String? createdAtIso;
  final String? callTimestampIso;
  final int durationSeconds;
  final String direction; // 'incoming' or 'outgoing'
  final bool isTableCall;
  final String tableNumber;
  final String section;
  final String? acknowledgedBy;

  const TrackerCallHistoryEntry({
    required this.eventKey,
    required this.callId,
    required this.customerName,
    this.callerRole,
    this.callerUserId,
    this.receiverUserId,
    required this.status,
    this.createdAtIso,
    this.callTimestampIso,
    this.durationSeconds = 0,
    this.direction = 'incoming',
    this.isTableCall = false,
    this.tableNumber = '',
    this.section = '',
    this.acknowledgedBy,
  });

  bool get isAccepted => status.toLowerCase() == 'accepted' || status.toLowerCase() == 'connected';
  bool get isDeclined => status.toLowerCase() == 'declined';
  bool get isMissed =>
      status.toLowerCase() == 'missed' ||
      status.toLowerCase() == 'offline' ||
      status.toLowerCase() == 'busy';

  bool get isOutgoing => direction.toLowerCase() == 'outgoing';
  bool get isIncoming => direction.toLowerCase() == 'incoming';

  bool get isDialed => isOutgoing;
  bool get isDialedAnswered => isOutgoing && isAccepted;
  bool get isReceived => isIncoming && isAccepted;
  bool get isIncomingMissed => isIncoming && !isAccepted;

  DateTime? get callTime => DateTime.tryParse(callTimestampIso ?? '')?.toLocal();
  DateTime? get createdAt => DateTime.tryParse(createdAtIso ?? '')?.toLocal();

  String get formattedDuration {
    if (durationSeconds <= 0) return '';
    final minutes = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  TrackerCallHistoryEntry copyWith({
    String? status,
    int? durationSeconds,
    String? acknowledgedBy,
  }) {
    return TrackerCallHistoryEntry(
      eventKey: eventKey,
      callId: callId,
      customerName: customerName,
      callerRole: callerRole,
      callerUserId: callerUserId,
      receiverUserId: receiverUserId,
      status: status ?? this.status,
      createdAtIso: createdAtIso,
      callTimestampIso: callTimestampIso,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      direction: direction,
      isTableCall: isTableCall,
      tableNumber: tableNumber,
      section: section,
      acknowledgedBy: acknowledgedBy ?? this.acknowledgedBy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventKey': eventKey,
      'callId': callId,
      'customerName': customerName,
      'callerRole': callerRole,
      'callerUserId': callerUserId,
      'receiverUserId': receiverUserId,
      'status': status,
      'createdAtIso': createdAtIso,
      'callTimestampIso': callTimestampIso,
      'durationSeconds': durationSeconds,
      'direction': direction,
      'isTableCall': isTableCall,
      'tableNumber': tableNumber,
      'section': section,
      'acknowledgedBy': acknowledgedBy,
    };
  }

  static TrackerCallHistoryEntry? fromJson(Map<String, dynamic> json) {
    try {
      return TrackerCallHistoryEntry(
        eventKey: json['eventKey']?.toString() ?? json['callId']?.toString() ?? '',
        callId: json['callId']?.toString() ?? json['eventKey']?.toString() ?? '',
        customerName: json['customerName']?.toString() ?? 'Staff',
        callerRole: json['callerRole']?.toString(),
        callerUserId: json['callerUserId']?.toString(),
        receiverUserId: json['receiverUserId']?.toString(),
        status: json['status']?.toString() ?? 'missed',
        createdAtIso: json['createdAtIso']?.toString(),
        callTimestampIso: json['callTimestampIso']?.toString(),
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        direction: json['direction']?.toString() ?? 'incoming',
        isTableCall: json['isTableCall'] == true,
        tableNumber: json['tableNumber']?.toString() ?? '',
        section: json['section']?.toString() ?? '',
        acknowledgedBy: json['acknowledgedBy']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

class TrackerCallHistoryService {
  TrackerCallHistoryService._();

  static const String _prefKey = 'tracker_call_history_cache_v1';
  static const int _maxEntries = 500;

  static List<TrackerCallHistoryEntry> _readEntriesFromPrefs(SharedPreferences prefs) {
    final raw = prefs.getString(_prefKey);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final list = <TrackerCallHistoryEntry>[];
      for (final item in decoded) {
        if (item is Map) {
          final entry = TrackerCallHistoryEntry.fromJson(Map<String, dynamic>.from(item));
          if (entry != null) list.add(entry);
        }
      }
      list.sort(_sortDesc);
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveEntriesToPrefs(
    SharedPreferences prefs,
    List<TrackerCallHistoryEntry> entries,
  ) async {
    final sorted = List<TrackerCallHistoryEntry>.from(entries)..sort(_sortDesc);
    final trimmed = sorted.length > _maxEntries ? sorted.sublist(0, _maxEntries) : sorted;
    await prefs.setString(
      _prefKey,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  static int _sortDesc(TrackerCallHistoryEntry a, TrackerCallHistoryEntry b) {
    final aTime = a.callTime?.millisecondsSinceEpoch ?? a.createdAt?.millisecondsSinceEpoch ?? 0;
    final bTime = b.callTime?.millisecondsSinceEpoch ?? b.createdAt?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  }

  static Future<List<TrackerCallHistoryEntry>> readHistory({bool syncRemote = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _readEntriesFromPrefs(prefs);
    if (syncRemote) {
      unawaited(syncHistoryFromBackend());
    }
    return cached;
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  static Future<void> recordVoiceCall({
    required String callId,
    required String callerName,
    String? callerRole,
    String? callerUserId,
    String status = 'missed',
    String direction = 'incoming',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = _readEntriesFromPrefs(prefs);
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final newEntry = TrackerCallHistoryEntry(
      eventKey: callId,
      callId: callId,
      customerName: callerName,
      callerRole: callerRole,
      callerUserId: callerUserId,
      status: status,
      createdAtIso: nowIso,
      callTimestampIso: nowIso,
      direction: direction,
    );

    final idx = entries.indexWhere((e) => e.callId == callId);
    if (idx >= 0) {
      entries[idx] = newEntry;
    } else {
      entries.insert(0, newEntry);
    }

    await _saveEntriesToPrefs(prefs, entries);
  }

  static Future<void> updateVoiceCallStatus({
    required String callId,
    required String status,
    int? durationSeconds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = _readEntriesFromPrefs(prefs);
    final idx = entries.indexWhere((e) => e.callId == callId);
    if (idx >= 0) {
      final old = entries[idx];
      entries[idx] = old.copyWith(
        status: status,
        durationSeconds: durationSeconds ?? old.durationSeconds,
      );
      await _saveEntriesToPrefs(prefs, entries);
    }
  }

  static Future<String?> _readToken() async {
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'token');
      if (token != null && token.trim().isNotEmpty) return token.trim();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? prefs.getString('auth_token');
      if (token != null && token.trim().isNotEmpty) return token.trim();
    } catch (_) {}
    return null;
  }

  static Future<List<TrackerCallHistoryEntry>> syncHistoryFromBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _readToken();
    if (token == null || token.isEmpty) return _readEntriesFromPrefs(prefs);

    String myUserId = '';
    try {
      const storage = FlutterSecureStorage();
      myUserId = (await storage.read(key: 'userId') ?? '').trim();
    } catch (_) {}
    if (myUserId.isEmpty) {
      myUserId = (prefs.getString('userId') ?? prefs.getString('user_id') ?? '').trim();
    }

    final localEntries = _readEntriesFromPrefs(prefs);
    final mergedMap = <String, TrackerCallHistoryEntry>{};
    for (final e in localEntries) {
      mergedMap[e.callId] = e;
    }

    // 1. Fetch Call Logs from backend
    try {
      final uri = Uri.parse('${ApiService.baseUrl}/call-logs?limit=300&sort=-createdAt&depth=0');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 7));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final docs = (decoded is Map ? decoded['docs'] : null) as List? ?? [];

        for (final doc in docs) {
          if (doc is! Map) continue;
          final callId = doc['callId']?.toString().trim();
          if (callId == null || callId.isEmpty) continue;

          final callerId = _relId(doc['callerUserId'] ?? doc['callerUser']);
          final receiverId = _relId(doc['receiverUserId'] ?? doc['receiverUser']);

          // Only keep calls where this user is caller or receiver
          final isCaller = myUserId.isNotEmpty && callerId == myUserId;
          final isReceiver = myUserId.isNotEmpty && receiverId == myUserId;

          if (myUserId.isNotEmpty && !isCaller && !isReceiver) continue;

          final rawStatus = doc['status']?.toString().toLowerCase() ?? 'missed';
          final status = (rawStatus == 'connected' || rawStatus == 'accepted')
              ? 'accepted'
              : (rawStatus == 'declined' ? 'declined' : 'missed');

          final durationSec = (doc['durationSeconds'] as num?)?.toInt() ?? 0;
          final createdAt = doc['createdAt']?.toString() ?? doc['startedAt']?.toString();

          final otherName = isCaller
              ? (doc['receiverName']?.toString().trim() ?? 'Staff')
              : (doc['callerName']?.toString().trim() ?? 'Admin');

          final otherRole = isCaller
              ? doc['receiverRole']?.toString()
              : doc['callerRole']?.toString();

          final entry = TrackerCallHistoryEntry(
            eventKey: callId,
            callId: callId,
            customerName: otherName.isNotEmpty ? otherName : 'Staff',
            callerRole: otherRole,
            callerUserId: isCaller ? receiverId : callerId,
            receiverUserId: isCaller ? callerId : receiverId,
            status: status,
            createdAtIso: createdAt,
            callTimestampIso: createdAt,
            durationSeconds: durationSec,
            direction: isCaller ? 'outgoing' : 'incoming',
          );

          final existing = mergedMap[callId];
          if (existing == null) {
            mergedMap[callId] = entry;
          } else {
            mergedMap[callId] = existing.copyWith(
              status: status,
              durationSeconds: durationSec > 0 ? durationSec : existing.durationSeconds,
            );
          }
        }
      }
    } catch (err) {
      debugPrint('TrackerCallHistoryService: error syncing call logs: $err');
    }

    final result = mergedMap.values.toList()..sort(_sortDesc);
    await _saveEntriesToPrefs(prefs, result);
    return result;
  }

  static String? _relId(dynamic val) {
    if (val == null) return null;
    if (val is String && val.trim().isNotEmpty) return val.trim();
    if (val is Map) {
      final id = val['id'] ?? val['_id'];
      if (id != null && id.toString().trim().isNotEmpty) return id.toString().trim();
    }
    return null;
  }

  static Future<String?> getLastAdminUserId() async {
    final token = await _readToken();
    if (token == null) return null;

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/users?where[role][in]=superadmin,admin&limit=5&depth=0');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final docs = (decoded is Map ? decoded['docs'] : null) as List? ?? [];
        if (docs.isNotEmpty) {
          final id = _relId(docs.first['id'] ?? docs.first['_id']);
          if (id != null && id.isNotEmpty) return id;
        }
      }
    } catch (_) {}
    return null;
  }
}
