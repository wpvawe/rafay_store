import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/category_model.dart';
import '../services/firestore_service.dart';

class CategoryProvider extends ChangeNotifier {
  CategoryProvider({FirestoreService? firestoreService})
      : _db = firestoreService ?? FirestoreService();

  final FirestoreService _db;
  List<CategoryModel> _categories = [];
  StreamSubscription<List<CategoryModel>>? _sub;
  String? _error;
  bool _isBusy = false;

  List<CategoryModel> get categories => [
        CategoryModel.general,
        ..._categories,
      ];

  String? get error => _error;
  bool get isBusy => _isBusy;

  void startListening() {
    _sub?.cancel();
    _sub = _db.watchCategories().listen(
      (list) {
        _categories = list;
        notifyListeners();
      },
      onError: (e) {
        _error = e.toString();
        notifyListeners();
      },
    );
  }

  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _setBusy(true);
    _error = null;
    try {
      await _db.addCategory(CategoryModel(id: '', name: trimmed));
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> updateCategory(CategoryModel category, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    _setBusy(true);
    _error = null;
    try {
      await _db.updateCategory(category.copyWith(name: trimmed));
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteCategory(String id) async {
    _setBusy(true);
    _error = null;
    try {
      await _db.deleteCategory(id);
    } catch (e) {
      _error = e.toString();
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool v) {
    _isBusy = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
