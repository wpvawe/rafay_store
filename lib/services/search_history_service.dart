import 'package:shared_preferences/shared_preferences.dart';

/// Persists the last [maxEntries] unique search queries for the demand list.
class SearchHistoryService {
  static const _key = 'demand_search_history';
  static const maxEntries = 5;

  /// Returns the saved history (most-recent first).
  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  /// Adds [query] to the top of the history list, deduplicates, and trims to
  /// [maxEntries]. Ignores blank / whitespace-only queries.
  static Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_key) ?? [];
    history.remove(q);
    history.insert(0, q);
    if (history.length > maxEntries) history.length = maxEntries;
    await prefs.setStringList(_key, history);
  }

  /// Removes a single entry from history.
  static Future<void> remove(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_key) ?? [];
    history.remove(query.trim());
    await prefs.setStringList(_key, history);
  }

  /// Wipes the entire history.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
