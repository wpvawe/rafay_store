import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

class PhoneContact {
  final String name;
  final String phone;

  const PhoneContact({required this.name, required this.phone});

  Map<String, dynamic> toMap() => {'name': name, 'phone': phone};
}

class ContactsService {
  ContactsService._();
  static final ContactsService instance = ContactsService._();

  List<PhoneContact> _contacts = [];
  bool _loaded = false;
  bool _permissionDenied = false;

  bool get isLoaded => _loaded;
  bool get permissionDenied => _permissionDenied;
  List<PhoneContact> get contacts => List.unmodifiable(_contacts);

  /// Request permission and load contacts. Returns true if successful.
  ///
  /// Uses flutter_contacts ^1.1.9 API:
  ///   FlutterContacts.getContacts(withProperties: true)
  Future<bool> loadContacts() async {
    if (_loaded) return true;

    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      _permissionDenied = true;
      return false;
    }

    try {
      final rawContacts = await FlutterContacts.getContacts(
        withProperties: true,
      );
      final result = <PhoneContact>[];

      for (final contact in rawContacts) {
        final name = contact.displayName.trim();
        if (name.isEmpty) continue;

        for (final phone in contact.phones) {
          final cleaned = _cleanNumber(phone.number);
          if (cleaned.isNotEmpty) {
            result.add(PhoneContact(name: name, phone: cleaned));
            break; // Only take the first valid phone per contact
          }
        }
      }

      _contacts = result;
      _loaded = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Find contacts by name (fuzzy search).
  List<PhoneContact> findByName(String query) {
    if (query.trim().isEmpty) return [];
    final q = query.toLowerCase().trim();
    return _contacts
        .where((c) => c.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) {
        final aExact = a.name.toLowerCase() == q ? 0 : 1;
        final bExact = b.name.toLowerCase() == q ? 0 : 1;
        if (aExact != bExact) return aExact.compareTo(bExact);
        return a.name.compareTo(b.name);
      });
  }

  /// Convert contacts list to maps for server upload.
  List<Map<String, dynamic>> toServerList() =>
      _contacts.map((c) => c.toMap()).toList();

  /// Normalize a raw phone number to E.164-style Pakistan format.
  String _cleanNumber(String raw) {
    String n = raw.replaceAll(RegExp(r'[\s\-().+]'), '');
    if (n.isEmpty) return '';

    if (n.startsWith('0') && n.length == 11) return '92${n.substring(1)}';
    if (n.startsWith('3') && n.length == 10) return '92$n';
    if (n.startsWith('92') && n.length == 12) return n;
    if (n.length >= 10) return n;
    return '';
  }

  void reset() {
    _contacts = [];
    _loaded = false;
    _permissionDenied = false;
  }
}
