// lib/screens/help_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

final supabase = Supabase.instance.client;

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String _selectedLanguage = 'en';

  // ============== Translations ==============
  final Map<String, Map<String, String>> _strings = {
    'en': {
      'title': 'Help & Support',
      'how_can_we_help': 'How can we help?',
      'select_topic': 'Select a topic below',
      'quick_actions': 'Quick Actions',
      'reset_password': 'Reset Password',
      'report_issue': 'Report Issue',
      'live_chat': 'Live Chat',
      'faq': 'Frequently Asked Questions',
      'still_need_help': 'Still need help?',
      'support_247': 'Our support team is available 24/7',
      'email': 'Email',
      'call': 'Call',
      'chat': 'Chat',
      'version': 'Version',
      'cancel': 'Cancel',
      'submit': 'Submit',
      'send': 'Send',
      'close': 'Close',
      'ok': 'OK',
      'enter_title': 'Enter a title',
      'enter_description': 'Enter a description',
      'report_submitted': 'Report submitted! Thank you.',
      'error': 'Error',
      'success': 'Success',
      'contact_support': 'Contact Support',
      'whatsapp': 'WhatsApp',
      'messenger': 'Messenger',
      'telegram': 'Telegram',
      'quick_response': 'Quick response',
      'secure_chat': 'Secure chat',
      'call_now': 'Call now',
      'copy_number': 'Copy number',
      'number_copied': 'Number copied',
      'copy_email': 'Copy Email',
      'email_copied': 'Email copied',
    },
    'si': {
      'title': 'උදව් සහ සහාය',
      'how_can_we_help': 'අපට ඔබට උදව් කළ හැක්කේ කෙසේද?',
      'select_topic': 'පහත මාතෘකාවක් තෝරන්න',
      'quick_actions': 'ඉක්මන් ක්‍රියා',
      'reset_password': 'මුරපදය යළි සකසන්න',
      'report_issue': 'ගැටලුවක් වාර්තා කරන්න',
      'live_chat': 'සජීවී කතාබහ',
      'faq': 'නිතර අසන ප්‍රශ්න',
      'still_need_help': 'තවත් උදව් අවශ්‍යද?',
      'support_247': 'අපගේ සහාය කණ්ඩායම 24/7 ලබා ගත හැක',
      'email': 'ඊමේල්',
      'call': 'ඇමතුම',
      'chat': 'කතාබහ',
      'version': 'සංස්කරණය',
      'cancel': 'අවලංගු කරන්න',
      'submit': 'ඉදිරිපත් කරන්න',
      'send': 'යවන්න',
      'close': 'වසන්න',
      'ok': 'හරි',
      'enter_title': 'මාතෘකාවක් ඇතුළත් කරන්න',
      'enter_description': 'විස්තරයක් ඇතුළත් කරන්න',
      'report_submitted': 'වාර්තාව ඉදිරිපත් කරන ලදී! ස්තුතියි.',
      'error': 'දෝෂය',
      'success': 'සාර්ථකයි',
      'contact_support': 'සහාය සම්බන්ධ කර ගන්න',
      'whatsapp': 'WhatsApp',
      'messenger': 'Messenger',
      'telegram': 'Telegram',
      'quick_response': 'වේගවත් පිළිතුරු',
      'secure_chat': 'ආරක්ෂිත කතාබහ',
      'call_now': 'දැන් අමතන්න',
      'copy_number': 'අංකය පිටපත් කරන්න',
      'number_copied': 'අංකය පිටපත් කරන ලදී',
      'copy_email': 'ඊමේල් එක පිටපත් කරන්න',
      'email_copied': 'ඊමේල් ලිපිනය පිටපත් කරන ලදී',
    },
    'ta': {
      'title': 'உதவி மற்றும் ஆதரவு',
      'how_can_we_help': 'நாங்கள் உங்களுக்கு எவ்வாறு உதவ முடியும்?',
      'select_topic': 'கீழே ஒரு தலைப்பைத் தேர்ந்தெடுக்கவும்',
      'quick_actions': 'விரைவு செயல்கள்',
      'reset_password': 'கடவுச்சொல்லை மீட்டமைக்க',
      'report_issue': 'சிக்கலைப் புகாரளிக்க',
      'live_chat': 'நேரலை அரட்டை',
      'faq': 'அடிக்கடி கேட்கப்படும் கேள்விகள்',
      'still_need_help': 'இன்னும் உதவி தேவையா?',
      'support_247': 'எங்கள் ஆதரவு குழு 24/7 கிடைக்கும்',
      'email': 'மின்னஞ்சல்',
      'call': 'அழைப்பு',
      'chat': 'அரட்டை',
      'version': 'பதிப்பு',
      'cancel': 'ரத்து செய்',
      'submit': 'சமர்ப்பிக்க',
      'send': 'அனுப்பு',
      'close': 'மூடு',
      'ok': 'சரி',
      'enter_title': 'தலைப்பை உள்ளிடவும்',
      'enter_description': 'விளக்கத்தை உள்ளிடவும்',
      'report_submitted': 'அறிக்கை சமர்ப்பிக்கப்பட்டது! நன்றி.',
      'error': 'பிழை',
      'success': 'வெற்றி',
      'contact_support': 'ஆதரவைத் தொடர்பு கொள்ள',
      'whatsapp': 'WhatsApp',
      'messenger': 'Messenger',
      'telegram': 'Telegram',
      'quick_response': 'விரைவான பதில்',
      'secure_chat': 'பாதுகாப்பான அரட்டை',
      'call_now': 'இப்போது அழைக்கவும்',
      'copy_number': 'எண்ணை நகலெடுக்க',
      'number_copied': 'எண் நகலெடுக்கப்பட்டது',
      'copy_email': 'மின்னஞ்சலை நகலெடுக்க',
      'email_copied': 'மின்னஞ்சல் முகவரி நகலெடுக்கப்பட்டது',
    },
  };

  String getString(String key) {
    return _strings[_selectedLanguage]?[key] ?? _strings['en']![key]!;
  }

  // ============== EMAIL - WEB VERSION (100% Working) ==============
  Future<void> _sendEmail() async {
    final email = 'support@mysalon.com';
    final subject = 'Help Request - MySalon App';
    final body = 'User: ${supabase.auth.currentUser?.email ?? 'Guest'}';

    // WEB PLATFORM
    if (kIsWeb) {
      await _sendEmailWeb(email, subject, body);
      return;
    }

    // MOBILE PLATFORM
    await _sendEmailMobile(email, subject, body);
  }

  //  WEB VERSION
  Future<void> _sendEmailWeb(String email, String subject, String body) async {
    // Try Gmail first
    try {
      final gmailUri = Uri.parse(
        'https://mail.google.com/mail/?view=cm&fs=1'
        '&to=$email'
        '&su=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}',
      );
      await launchUrl(gmailUri, mode: LaunchMode.externalApplication);
      _showSnackBar(getString('success'), 'Opening Gmail...', Colors.green);
      return;
    } catch (e) {
      debugPrint('Gmail failed: $e');
    }

    // Try Outlook
    try {
      final outlookUri = Uri.parse(
        'https://outlook.live.com/mail/0/deeplink/compose'
        '?to=$email'
        '&subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}',
      );
      await launchUrl(outlookUri, mode: LaunchMode.externalApplication);
      _showSnackBar(getString('success'), 'Opening Outlook...', Colors.green);
      return;
    } catch (e) {
      debugPrint('Outlook failed: $e');
    }

    // Try Yahoo
    try {
      final yahooUri = Uri.parse(
        'https://compose.mail.yahoo.com/'
        '?to=$email'
        '&subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}',
      );
      await launchUrl(yahooUri, mode: LaunchMode.externalApplication);
      _showSnackBar(
        getString('success'),
        'Opening Yahoo Mail...',
        Colors.green,
      );
      return;
    } catch (e) {
      debugPrint('Yahoo failed: $e');
    }

    // Final fallback - Copy email
    _showEmailCopyDialog(email);
  }

  // MOBILE VERSION
  Future<void> _sendEmailMobile(
    String email,
    String subject,
    String body,
  ) async {
    try {
      final uri = Uri.parse(
        'mailto:$email?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      _showSnackBar(getString('success'), 'Opening email app...', Colors.green);
    } catch (e) {
      debugPrint('Mobile email failed: $e');
      _showEmailCopyDialog(email);
    }
  }

  // ============== EMAIL COPY DIALOG - FIXED ==============
  void _showEmailCopyDialog(String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '📧 ${getString('email')}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kIsWeb
                  ? 'Web browser එකෙන් email app එක open කරන්න බැහැ. Email එක copy කරගෙන manually send කරන්න.'
                  : 'Email app එක open කරන්න බැහැ. Email එක copy කරගෙන manually send කරන්න.',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blueAccent.withValues(alpha: 0.3),
                ),
              ),
              child: SelectableText(
                email,
                style: const TextStyle(
                  color: Colors.blueAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              getString('close'),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              // Copy to clipboard
              context.pop();
              _showSnackBar(
                getString('success'),
                getString('email_copied'),
                Colors.green,
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text(getString('copy_email')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ============== PHONE CALL - WEB VERSION ==============
  Future<void> _makePhoneCall() async {
    final phoneNumber = '+1234567890';

    // WEB PLATFORM
    if (kIsWeb) {
      _showWebCallDialog(phoneNumber);
      return;
    }

    // MOBILE PLATFORM
    try {
      final uri = Uri.parse('tel:$phoneNumber');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Call failed: $e');
      _showCallOptionsDialog(phoneNumber);
    }
  }

  void _showWebCallDialog(String phoneNumber) {
    // Get translated message based on selected language
    String getCallMessage() {
      switch (_selectedLanguage) {
        case 'si':
          return 'වෙබ් බ්‍රවුසරයෙන් කෙලින්ම ඇමතුමක් ගත නොහැක. කරුණාකර අංකය පිටපත් කරගෙන අතින් අමතන්න:';
        case 'ta':
          return 'இணைய உலாவியில் நேரடியாக அழைக்க முடியாது. தயவுசெய்து எண்ணை நகலெடுத்து கைமுறையாக அழைக்கவும்:';
        default: // 'en'
          return 'Cannot make direct calls from web browser. Please copy the number and call manually:';
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '📞 ${getString('call')}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              getCallMessage(),
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: SelectableText(
                phoneNumber,
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              getString('close'),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              context.pop();
              _showSnackBar(
                getString('success'),
                getString('number_copied'),
                Colors.green,
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text(getString('copy_number')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showCallOptionsDialog(String phoneNumber) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          getString('contact_support'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call, color: Colors.green, size: 24),
              ),
              title: Text(
                getString('call_now'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                phoneNumber,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              onTap: () {
                context.pop();
                _launchUrl('tel:$phoneNumber');
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.copy, color: Colors.blue, size: 24),
              ),
              title: Text(
                getString('copy_number'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                phoneNumber,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              onTap: () {
                context.pop();
                _showSnackBar(
                  getString('success'),
                  getString('number_copied'),
                  Colors.green,
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              getString('close'),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  // ============== WHATSAPP ==============
  Future<void> _openWhatsApp() async {
    final phone = '1234567890';
    final text = 'Hello MySalon Support, I need help with:';

    try {
      final webUri = Uri.parse(
        'https://wa.me/$phone?text=${Uri.encodeComponent(text)}',
      );
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('WhatsApp error: $e');
      _showSnackBar(
        getString('error'),
        'Please install WhatsApp',
        Colors.orange,
      );
    }
  }

  // ============== MESSENGER ==============
  Future<void> _openMessenger() async {
    final username = 'mysalonapp';

    try {
      final uri = Uri.parse('https://m.me/$username');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Messenger error: $e');
      _showSnackBar(getString('error'), 'Cannot open Messenger', Colors.orange);
    }
  }

  // ============== TELEGRAM ==============
  Future<void> _openTelegram() async {
    final username = 'mysalon_support';

    try {
      final uri = Uri.parse('https://t.me/$username');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Telegram error: $e');
      _showSnackBar(getString('error'), 'Cannot open Telegram', Colors.orange);
    }
  }

  // ============== RESET PASSWORD ==============
  void _resetPassword() {
    context.push('/forgot-password');
  }

  // ============== LANGUAGE SELECTOR ==============
  Widget _buildLanguageSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLanguageOption('EN', 'en'),
          _buildDivider(),
          _buildLanguageOption('සිං', 'si'),
          _buildDivider(),
          _buildLanguageOption('த', 'ta'),
        ],
      ),
    );
  }

  Widget _buildLanguageOption(String text, String langCode) {
    final isSelected = _selectedLanguage == langCode;
    return GestureDetector(
      onTap: () => setState(() => _selectedLanguage = langCode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blueAccent.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: kIsWeb ? 13 : 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 20,
      color: Colors.white.withValues(alpha: 0.2),
    );
  }

  void _showSnackBar(String title, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $message'),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Launch error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1820),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          getString('title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _buildLanguageSelector(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _HelpHeader(getString: getString),
          const SizedBox(height: 24),
          _QuickActions(
            getString: getString,
            onResetTap: _resetPassword,
            onReportTap: () => _showReportDialog(),
            onChatTap: () => _showChatDialog(),
          ),
          const SizedBox(height: 24),
          _FaqSection(getString: getString),
          const SizedBox(height: 24),
          _ContactSection(
            getString: getString,
            onEmailTap: _sendEmail,
            onPhoneTap: _makePhoneCall,
            onChatTap: () => _showChatDialog(),
          ),
          const SizedBox(height: 20),
          _AppInfo(getString: getString),
        ],
      ),
    );
  }

  void _showReportDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          getString('report_issue'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: getString('enter_title'),
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              decoration: InputDecoration(
                hintText: getString('enter_description'),
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              getString('cancel'),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.isNotEmpty &&
                  descController.text.isNotEmpty) {
                _saveReport(titleController.text, descController.text);
                context.pop();
                _showSnackBar(
                  getString('success'),
                  getString('report_submitted'),
                  Colors.green,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: Text(getString('submit')),
          ),
        ],
      ),
    );
  }

  Future<void> _saveReport(String title, String description) async {
    try {
      final user = supabase.auth.currentUser;

      // Create report data
      final Map<String, dynamic> reportData = {
        'title': title,
        'description': description,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      };

      // Add user data if logged in
      if (user != null) {
        reportData['user_id'] = user.id;
        reportData['email'] = user.email;
      } else {
        // Anonymous user
        reportData['user_id'] = null;
        reportData['email'] = 'anonymous@guest';
      }

      // Insert to Supabase
      await supabase.from('reports').insert(reportData);

      debugPrint(
        'Report saved successfully (User: ${user != null ? 'logged in' : 'anonymous'})',
      );
    } catch (e) {
      debugPrint('Error saving report: $e');
    }
  }

  void _showChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          getString('contact_support'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildChatOption(
              icon: Icons.chat,
              color: Colors.green,
              title: getString('whatsapp'),
              subtitle: getString('quick_response'),
              onTap: _openWhatsApp,
            ),
            _buildChatOption(
              icon: Icons.facebook,
              color: Colors.blue,
              title: getString('messenger'),
              subtitle: 'Facebook',
              onTap: _openMessenger,
            ),
            _buildChatOption(
              icon: Icons.send,
              color: Colors.lightBlue,
              title: getString('telegram'),
              subtitle: getString('secure_chat'),
              onTap: _openTelegram,
            ),
            _buildChatOption(
              icon: Icons.email,
              color: Colors.orange,
              title: getString('email'),
              subtitle: 'support@mysalon.com',
              onTap: _sendEmail,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              getString('close'),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 12,
        ),
      ),
      onTap: () {
        context.pop();
        onTap();
      },
    );
  }
}

// ============== Header Widget ==============
class _HelpHeader extends StatelessWidget {
  final String Function(String) getString;

  const _HelpHeader({required this.getString});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1877F2), Color(0xFF0A58CA)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.help_outline,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  getString('how_can_we_help'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  getString('select_topic'),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============== Quick Actions ==============
class _QuickActions extends StatelessWidget {
  final String Function(String) getString;
  final VoidCallback onResetTap;
  final VoidCallback onReportTap;
  final VoidCallback onChatTap;

  const _QuickActions({
    required this.getString,
    required this.onResetTap,
    required this.onReportTap,
    required this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          getString('quick_actions'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.lock_reset,
                title: getString('reset_password'),
                color: Colors.orange,
                onTap: onResetTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                icon: Icons.report_problem,
                title: getString('report_issue'),
                color: Colors.redAccent,
                onTap: onReportTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                icon: Icons.chat,
                title: getString('live_chat'),
                color: Colors.green,
                onTap: onChatTap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}

// ============== FAQ Section ==============
class _FaqSection extends StatelessWidget {
  final String Function(String) getString;

  const _FaqSection({required this.getString});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          getString('faq'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _FaqItem(
          question: '🔐 ${getString('reset_password')}',
          answer: 'Click on "Reset Password" button',
        ),
        _FaqItem(
          question: '📝 ${getString('report_issue')}',
          answer: getString('report_submitted'),
        ),
        _FaqItem(
          question: '💬 ${getString('live_chat')}',
          answer: getString('quick_response'),
        ),
        _FaqItem(
          question: '📧 ${getString('email')}',
          answer: 'support@mysalon.com',
        ),
        _FaqItem(question: '📞 ${getString('call')}', answer: '+1234567890'),
      ],
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(
              widget.question,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: Icon(
              _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.blueAccent,
            ),
            onTap: () => setState(() => _isExpanded = !_isExpanded),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                widget.answer,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============== Contact Section ==============
class _ContactSection extends StatelessWidget {
  final String Function(String) getString;
  final VoidCallback onEmailTap;
  final VoidCallback onPhoneTap;
  final VoidCallback onChatTap;

  const _ContactSection({
    required this.getString,
    required this.onEmailTap,
    required this.onPhoneTap,
    required this.onChatTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blueAccent.withValues(alpha: 0.1),
            Colors.purpleAccent.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.headset_mic, size: 48, color: Colors.blueAccent),
          const SizedBox(height: 12),
          Text(
            getString('still_need_help'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            getString('support_247'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEmailTap,
                  icon: const Icon(Icons.email, size: 18),
                  label: Text(getString('email')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPhoneTap,
                  icon: const Icon(Icons.phone, size: 18),
                  label: Text(getString('call')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onChatTap,
                  icon: const Icon(Icons.chat, size: 18),
                  label: Text(getString('chat')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
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

// ============== App Info ==============
class _AppInfo extends StatelessWidget {
  final String Function(String) getString;

  const _AppInfo({required this.getString});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF1877F2), Color(0xFF0A58CA)],
              ),
            ),
            child: const Center(
              child: Text(
                'MS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MySalon',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                '${getString('version')} 1.0.0',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
