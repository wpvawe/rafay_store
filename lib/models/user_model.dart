import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants.dart';

/// Represents a store user stored in Firestore.
class UserModel {
  final String uid;
  final String name;
  final String email;
  final String role; // AppConstants.roleAdmin / roleEditor / roleViewer
  final String status; // AppConstants.statusPending / statusApproved / statusRejected
  final String? fcmToken;
  final DateTime createdAt;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.fcmToken,
    required this.createdAt,
  });

  bool get isAdmin => role == AppConstants.roleAdmin;
  bool get isEditor => role == AppConstants.roleEditor;
  bool get isViewer => role == AppConstants.roleViewer;
  bool get isApproved => status == AppConstants.statusApproved;
  bool get canWrite => isAdmin || isEditor;

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? AppConstants.roleViewer,
      status: data['status'] as String? ?? AppConstants.statusPending,
      fcmToken: data['fcmToken'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'email': email,
    'role': role,
    'status': status,
    if (fcmToken != null) 'fcmToken': fcmToken,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  UserModel copyWith({
    String? name,
    String? email,
    String? role,
    String? status,
    String? fcmToken,
  }) => UserModel(
    uid: uid,
    name: name ?? this.name,
    email: email ?? this.email,
    role: role ?? this.role,
    status: status ?? this.status,
    fcmToken: fcmToken ?? this.fcmToken,
    createdAt: createdAt,
  );
}
