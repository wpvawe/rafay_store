import 'package:cloud_firestore/cloud_firestore.dart';

class CategoryModel {
  final String id;
  final String name;

  const CategoryModel({required this.id, required this.name});

  static const CategoryModel general =
      CategoryModel(id: 'general', name: 'General');

  factory CategoryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CategoryModel(
      id: doc.id,
      name: data['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {'name': name};

  CategoryModel copyWith({String? name}) =>
      CategoryModel(id: id, name: name ?? this.name);
}
