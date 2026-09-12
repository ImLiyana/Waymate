class AppUser {
  final String uid;
  final String name;
  final String phone;
  final String role; // "tourist" or "guide"
  final String? groupId;
  final String? emergencyContactPhone;

  AppUser({
    required this.uid,
    required this.name,
    required this.phone,
    required this.role,
    this.groupId,
    this.emergencyContactPhone,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'role': role,
      'groupId': groupId,
      'emergencyContactPhone': emergencyContactPhone,
    };
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      role: map['role'] ?? 'tourist',
      groupId: map['groupId'],
      emergencyContactPhone: map['emergencyContactPhone'],
    );
  }
}