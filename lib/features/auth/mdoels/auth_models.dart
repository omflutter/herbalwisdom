import 'dart:math';

class AppUser {
  final String id;
  final String phone;
  final String? fullName;
  final String? email;

  AppUser({required this.id, required this.phone, this.fullName, this.email});

  AppUser copyWith({String? id, String? phone, String? fullName}) =>
      AppUser(id: id ?? this.id, phone: phone ?? this.phone, fullName: fullName ?? this.fullName,email: email ?? this.email);
}
