import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_messenger/utils/contact_utils.dart';

void main() {
  test('ContactVCard to/from vCard string roundtrip', () {
    const name = 'John Doe';
    const phone = '+15551234567';
    const email = 'john.doe@example.com';

    final vcard = ContactVCard(name: name, phone: phone, email: email).toVCardString();
    final parsed = ContactVCard.fromVCardString(vcard);

    expect(parsed, isNotNull);
    expect(parsed!.name, name);
    expect(parsed.phone, phone);
    expect(parsed.email, email);
  });

  test('ContactVCard fromVCardString returns null for invalid input', () {
    expect(ContactVCard.fromVCardString(''), isNull);
    expect(ContactVCard.fromVCardString('BEGIN:VCARD\nEND:VCARD'), isNull);
    expect(ContactVCard.fromVCardString('BEGIN:VCARD\nFN:Alice\nEND:VCARD'), isNull);
  });
}
