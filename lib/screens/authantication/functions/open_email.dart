import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> openEmailApp(BuildContext context, String? userEmail) async {
  try {
    Uri? emailUri;

    if (kIsWeb) {
      final domain = userEmail?.split('@').last.toLowerCase() ?? '';
      if (domain.contains('gmail')) {
        emailUri = Uri.parse('https://mail.google.com/mail/u/0/#inbox');
      } else if (domain.contains('yahoo')) {
        emailUri = Uri.parse('https://mail.yahoo.com/');
      } else if (domain.contains('outlook') ||
          domain.contains('hotmail') ||
          domain.contains('live')) {
        emailUri = Uri.parse('https://outlook.live.com/mail/inbox');
      } else {
        emailUri = Uri.parse('https://mail.google.com/');
      }

      await launchUrl(emailUri, mode: LaunchMode.platformDefault);
    } else if (Platform.isAndroid || Platform.isIOS) {
      emailUri = Uri(scheme: 'mailto');

      if (!await canLaunchUrl(emailUri)) {
        emailUri = Uri.parse('https://mail.google.com/');
      }

      await launchUrl(emailUri, mode: LaunchMode.externalApplication);
    } else {
      emailUri = Uri(scheme: 'mailto');
      await launchUrl(emailUri, mode: LaunchMode.externalApplication);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't open your email app. Please open manually."),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    }
  }
}
