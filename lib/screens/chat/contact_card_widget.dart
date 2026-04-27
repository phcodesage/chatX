import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../utils/contact_utils.dart';

class ContactCardWidget extends StatefulWidget {
  const ContactCardWidget({
    super.key,
    required this.vcard,
    required this.isSentByMe,
  });

  final String vcard;
  final bool isSentByMe;

  @override
  State<ContactCardWidget> createState() => _ContactCardWidgetState();
}

class _ContactCardWidgetState extends State<ContactCardWidget> {
  bool _saving = false;
  bool _saved = false;
  bool _alreadyExists = false;

  @override
  void initState() {
    super.initState();
    _checkExistingContact();
  }

  Future<void> _checkExistingContact() async {
    final card = ContactVCard.fromVCardString(widget.vcard);
    if (card == null) return;

    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted || !mounted) return;

    final rawContacts = await FlutterContacts.getContacts(
      withProperties: true,
    );

    final normalizedPhone = card.phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final found = rawContacts.any((c) {
      final phones = c.phones
          .map((p) => p.number.replaceAll(RegExp(r'[\s\-\(\)]'), ''))
          .toList();
      return phones.contains(normalizedPhone);
    });

    if (found && mounted) {
      setState(() {
        _alreadyExists = true;
        _saved = true;
      });
    }
  }

  Future<void> _saveContact(ContactVCard card) async {
    setState(() => _saving = true);
    try {
      final granted = await FlutterContacts.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Contacts permission denied'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final parts = card.name.trim().split(' ');
      final newContact = Contact()
        ..name.first = parts.first
        ..name.last = parts.length > 1 ? parts.skip(1).join(' ') : ''
        ..phones = [Phone(card.phone)];
      if (card.email != null && card.email!.isNotEmpty) {
        newContact.emails = [Email(card.email!)];
      }

      await FlutterContacts.insertContact(newContact);

      if (mounted) {
        setState(() => _saved = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${card.name} saved to contacts')),
        );
      }
    } catch (e) {
      debugPrint('Save contact error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save contact')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = ContactVCard.fromVCardString(widget.vcard);

    if (card == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Contact', style: TextStyle(color: Colors.white70)),
      );
    }

    final initials = card.name.trim().isNotEmpty
        ? card.name
            .trim()
            .split(' ')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0])
            .take(2)
            .join()
            .toUpperCase()
        : '?';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF475569),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      card.phone,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _alreadyExists || _saving
                      ? null
                      : () => _saveContact(card),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                  ),
                  child: Text(
                    _alreadyExists
                        ? 'Already Saved'
                        : _saved
                            ? 'Saved'
                            : 'Save Contact',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
