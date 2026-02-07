/// Represents the authenticated user returned by the auth API.
class User {
  final String id;
  final String phoneNumber;

  const User({
    required this.id,
    required this.phoneNumber,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      phoneNumber: json['phone_number'] as String,
    );
  }
}
