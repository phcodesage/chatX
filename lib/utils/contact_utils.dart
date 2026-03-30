/// Utilities for vCard (VCF) generation and parsing used by contact messages.
class ContactVCard {
  final String name;
  final String phone;
  final String? email;

  const ContactVCard({required this.name, required this.phone, this.email});

  /// Generate a vCard 3.0 string from contact fields.
  String toVCardString() {
    final buffer = StringBuffer()
      ..writeln('BEGIN:VCARD')
      ..writeln('VERSION:3.0')
      ..writeln('FN:$name')
      ..writeln('TEL;TYPE=CELL:$phone');
    if (email != null && email!.isNotEmpty) {
      buffer.writeln('EMAIL:$email');
    }
    buffer.writeln('END:VCARD');
    return buffer.toString();
  }

  /// Parse a vCard string. Returns null if it is not a valid vCard.
  static ContactVCard? fromVCardString(String vcard) {
    String? name;
    String? phone;
    String? email;

    for (final rawLine in vcard.split('\n')) {
      final line = rawLine.trim();
      final upper = line.toUpperCase();
      if (upper.startsWith('FN:')) {
        name = line.substring(3).trim();
      } else if (upper.startsWith('TEL') && line.contains(':')) {
        phone = line.substring(line.indexOf(':') + 1).trim();
      } else if (upper.startsWith('EMAIL') && line.contains(':')) {
        email = line.substring(line.indexOf(':') + 1).trim();
      }
    }

    if (name == null || name.isEmpty || phone == null || phone.isEmpty) {
      return null;
    }
    return ContactVCard(name: name, phone: phone, email: email);
  }
}
