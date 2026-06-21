import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AiMessage {
  final String role;
  final String content;
  final DateTime timestamp;
  AiMessage({required this.role, required this.content, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

class AiActionResult {
  final String type;
  final bool success;
  final String message;
  final Map<String, dynamic> raw;

  const AiActionResult({
    required this.type,
    required this.success,
    required this.message,
    required this.raw,
  });

  factory AiActionResult.fromMap(Map<String, dynamic> map) {
    return AiActionResult(
      type: map['type'] as String? ?? '',
      success: map['success'] as bool? ?? false,
      message: map['message'] as String? ?? '',
      raw: map,
    );
  }

  bool get isWhatsApp => type == 'whatsapp';
}

class AiChatResult {
  final String reply;
  final AiActionResult? actionResult;
  final bool success;
  final String? error;

  const AiChatResult({
    required this.reply,
    this.actionResult,
    required this.success,
    this.error,
  });
}

class AiService {
  AiService._();
  static final AiService instance = AiService._();

  static const String _baseUrl = String.fromEnvironment(
    'AI_API_BASE_URL',
    defaultValue: 'https://rafay-store00.vercel.app/api',
  );

  // ── Persistent chat state ──────────────────────────────────────────────────
  final List<AiMessage> displayMessages = [];
  final List<AiMessage> apiMessages = [];
  bool _welcomeShown = false;

  static const String welcomeContent =
      'Hello Admin! 👋\n\n'
      'I\'m the **Rafay Store AI** — I have **full read + write access** to your store data.\n\n'
      '**📋 VIEW / LIST:**\n'
      '• "Show pending items"\n'
      '• "Show urgent items"\n'
      '• "Show all available items"\n'
      '• "List all customers"\n'
      '• "List all suppliers"\n'
      '• "Show udhaar summary"\n'
      '• "Show all categories"\n'
      '• "Show low stock items"\n'
      '• "Show out of stock items"\n\n'
      '**➕ ADD (Single & Bulk):**\n'
      '• "Add Rice to demand list"\n'
      '• "Add customer Ali, phone 0300-1234567"\n'
      '• "Add supplier Karachi Traders, WhatsApp 0321-9876543"\n'
      '• "Bulk add: Rice, Wheat, Sugar, Salt"\n'
      '• "Add category Ration"\n'
      '• "Add udhaar: Ali ne 5000 liye"\n\n'
      '**✏️ UPDATE (Single & Bulk):**\n'
      '• "Mark Sugar as available"\n'
      '• "Mark all urgent items as pending"\n'
      '• "Set quantity of Wheat to 50 kg"\n'
      '• "Set sell price of Rice to Rs 200"\n'
      '• "Set sell price of all Ration items to Rs 250"\n'
      '• "Update Ali ka udhaar to 8000"\n'
      '• "Assign Rice to Ration category"\n'
      '• "Assign all pending items to General category"\n'
      '• "Update stock of Sugar to 100"\n'
      '• "Set reorder level of Wheat to 20"\n'
      '• "Mark Ali udhaar as settled"\n\n'
      '**🗑️ DELETE (Single & Bulk):**\n'
      '• "Delete item named Rice"\n'
      '• "Delete all deferred items"\n'
      '• "Delete customer named Bilal"\n'
      '• "Delete supplier Karachi Traders"\n'
      '• "Delete all items in Ration category"\n\n'
      '**💰 PRICING & ANALYTICS:**\n'
      '• "Show pricing analytics"\n'
      '• "Total cost of all pending items"\n'
      '• "What is our profit margin?"\n'
      '• "Show items with sell price under Rs 300"\n\n'
      '**📱 WHATSAPP:**\n'
      '• "Message 0300-1234567"\n'
      '• "WhatsApp Ali Supplier"\n'
      '• "Send pending list to Karachi Traders"\n\n'
      '**📄 PAGINATION:**\n'
      '• First request returns first 100 records\n'
      '• Type "Next" or "Next 100" for more\n\n'
      '**⛔ WHAT I CANNOT DO:**\n'
      '• Navigate to a specific screen for you\n'
      '• Print receipts or generate PDF\n'
      '• Upload/change images or logos\n'
      '• Send SMS (only WhatsApp)\n\n'
      'How can I help you?';

  void ensureWelcome() {
    if (!_welcomeShown || displayMessages.isEmpty) {
      if (displayMessages.isEmpty) {
        displayMessages.add(
          AiMessage(role: 'assistant', content: welcomeContent),
        );
      }
      _welcomeShown = true;
    }
  }

  void clearHistory() {
    displayMessages.clear();
    apiMessages.clear();
    _welcomeShown = false;
    ensureWelcome();
  }

  /// Directly send a WhatsApp message without going through the AI.
  /// Used for the Retry button after a failed send.
  Future<AiActionResult> directSendWhatsApp({
    required String phone,
    required String message,
  }) async {
    try {
      final token = await _getIdToken();
      if (token == null) {
        return const AiActionResult(
          type: 'whatsapp',
          success: false,
          message: '❌ Authentication error',
          raw: {},
        );
      }
      final response = await http
          .post(
            Uri.parse('$_baseUrl/whatsapp/send'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'phone': phone, 'message': message}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return AiActionResult.fromMap(data);
      }
      return AiActionResult(
        type: 'whatsapp',
        success: false,
        message: '❌ Retry failed (${response.statusCode})',
        raw: {},
      );
    } catch (e) {
      return AiActionResult(
        type: 'whatsapp',
        success: false,
        message: '❌ Retry error: $e',
        raw: {},
      );
    }
  }

  /// Returns a valid Firebase ID token, or null if the user is genuinely
  /// signed out. Retries once on network/transient errors so a brief
  /// connectivity blip doesn't result in a false "session expired" message.
  Future<String?> _getIdToken({bool forceRefresh = false}) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return null; // genuinely signed out

        if (forceRefresh) {
          // reload() re-syncs the Firebase session before requesting a new
          // token — prevents returning a stale cached token.
          await user.reload();
        }

        // Re-read after reload — reload() updates the singleton.
        final freshUser = FirebaseAuth.instance.currentUser;
        if (freshUser == null) return null;

        return await freshUser.getIdToken(forceRefresh);
      } on FirebaseAuthException catch (e) {
        // user-token-expired, user-not-found etc. → real auth failure, no retry
        debugPrint('[AiService] FirebaseAuthException getting token: ${e.code}');
        return null;
      } catch (e) {
        // Network / socket error — retry once then give up
        debugPrint('[AiService] Transient error getting token (attempt $attempt): $e');
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          continue;
        }
        // Return null on persistent network issue so caller shows network error
        return null;
      }
    }
    return null;
  }


  /// Send a chat request to the AI server.
  ///
  /// [relevantContacts] — ONLY the contacts relevant to this specific message
  /// (already filtered by the caller, max ~10). Never pass the full contact
  /// list here — that causes 413 errors. The caller is responsible for
  /// extracting only the contacts that match the current query.
  Future<AiChatResult> chat(
    List<AiMessage> messages, {
    List<Map<String, dynamic>> relevantContacts = const [],
  }) async {
    // Initial token fetch — try with forceRefresh=false first (fast path).
    // If that returns null, try once more with forceRefresh=true before giving up.
    String? currentToken = await _getIdToken();
    if (currentToken == null) {
      // Could be a cold start — try a forced refresh once
      debugPrint('[AiService] Initial token null — trying force refresh');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      currentToken = await _getIdToken(forceRefresh: true);
    }
    if (currentToken == null) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return const AiChatResult(
          reply: '🔐 Aap logged in nahi hain.\n\nKripya pehle Login karein.',
          success: false,
          error: 'Not authenticated',
        );
      }
      return const AiChatResult(
        reply: '📶 Token nahi mila — Internet connection check karein aur dobara try karein.',
        success: false,
        error: 'Token fetch failed',
      );
    }

    final payload = {
      'messages': messages
          .map((m) => {'role': m.role, 'content': m.content})
          .toList(),
      if (relevantContacts.isNotEmpty) 'phoneContacts': relevantContacts,
    };

    // Try up to 2 times (once + 1 retry) for transient network / token errors
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse('$_baseUrl/ai/chat'),
              headers: {
                'Authorization': 'Bearer $currentToken',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 120));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final reply = data['reply'] as String? ?? '';

          AiActionResult? actionResult;
          final rawAction = data['actionResult'];
          if (rawAction is Map<String, dynamic>) {
            actionResult = AiActionResult.fromMap(rawAction);
          }

          return AiChatResult(
              reply: reply, actionResult: actionResult, success: true);
        } else if (response.statusCode == 413) {
          return const AiChatResult(
            reply: '⚠️ Request bahut badi thi — dobara try karein.',
            success: false,
            error: 'Payload too large',
          );
        } else if (response.statusCode == 403) {
          return const AiChatResult(
            reply: 'Yeh feature sirf admin ke liye hai.',
            success: false,
            error: 'Forbidden',
          );
        } else if (response.statusCode == 401) {
          if (attempt < 2) {
            // Token may have expired on the server — force-refresh and retry.
            // Give Firebase a moment to propagate the new token.
            debugPrint('[AiService] 401 received — force-refreshing token (attempt $attempt)');
            await Future<void>.delayed(const Duration(milliseconds: 500));
            final freshToken = await _getIdToken(forceRefresh: true);
            if (freshToken != null) {
              currentToken = freshToken;
            }
            await Future<void>.delayed(const Duration(milliseconds: 300));
            continue;
          }
          // Both attempts failed with 401 → genuine auth issue
          return const AiChatResult(
            reply: '🔐 Session expire ho gayi hai.\n\n'
                'Kripya app mein Logout karein aur dobara Login karein.\n'
                'Agar masla jari rahe to app band karke dobara kholein.',
            success: false,
            error: 'Unauthorized',
          );
        } else if (response.statusCode == 503) {
          // Server busy (Firestore quota/rate limit) — wait then retry
          if (attempt < 2) {
            debugPrint('[AiService] 503 — server busy, retrying after 30s...');
            await Future<void>.delayed(const Duration(seconds: 30));
            continue;
          }
          return const AiChatResult(
            reply: '⏳ Server abhi busy hai (Firestore limit).\n\n'
                'Thodi der ruk kar dobara try karein — 1-2 minute mein theek ho jayega.',
            success: false,
            error: 'Service unavailable',
          );
        } else if (response.statusCode >= 500 && attempt < 2) {
          // Server error — retry once after short delay
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        } else {
          return AiChatResult(
            reply:
                'Server error (${response.statusCode}). Thodi der baad try karen.',
            success: false,
            error: 'Status ${response.statusCode}',
          );
        }
      } on TimeoutException {
        if (attempt < 2) {
          // Retry on timeout once
          await Future<void>.delayed(const Duration(seconds: 1));
          continue;
        }
        return const AiChatResult(
          reply:
              '⏱️ Request timeout — server busy hai. Thodi der baad dobara try karen.',
          success: false,
          error: 'Timeout',
        );
      } on SocketException {
        return const AiChatResult(
          reply:
              '📶 Internet connection nahi hai. Network check karen aur dobara try karen.',
          success: false,
          error: 'No internet',
        );
      } catch (e) {
        return AiChatResult(
          reply: 'Connection error. Internet check karen.\n\nDetail: $e',
          success: false,
          error: e.toString(),
        );
      }
    }

    // Should never reach here
    return const AiChatResult(
      reply: 'Unknown error. Dobara try karen.',
      success: false,
      error: 'Unknown',
    );
  }
}
