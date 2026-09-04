// lib/screens/help_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_application_1/utils/app_version.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

final supabase = Supabase.instance.client;

class HelpScreen extends StatefulWidget {
  final String screenType; // 'help', 'contact', 'about'

  const HelpScreen({super.key, required this.screenType});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  String _selectedLanguage = 'en';

  // ✅ Responsive breakpoints
  bool _isTablet = false;
  bool _isWeb = false;
  bool _isSmallPhone = false; // < 360 logical px wide

  // ============== TRANSLATIONS ==============
  final Map<String, Map<String, String>> _strings = {
    // ===== SHARED =====
    'en': {
      'email': 'Email',
      'call': 'Call',
      'chat': 'Chat',
      'version': 'Version',
      'cancel': 'Cancel',
      'submit': 'Submit',
      'close': 'Close',
      'ok': 'OK',
      'success': 'Success',
      'error': 'Error',
    },
    'si': {
      'email': 'ඊමේල්',
      'call': 'ඇමතුම',
      'chat': 'කතාබහ',
      'version': 'සංස්කරණය',
      'cancel': 'අවලංගු කරන්න',
      'submit': 'ඉදිරිපත් කරන්න',
      'close': 'වසන්න',
      'ok': 'හරි',
      'success': 'සාර්ථකයි',
      'error': 'දෝෂය',
    },
    'ta': {
      'email': 'மின்னஞ்சல்',
      'call': 'அழைப்பு',
      'chat': 'அரட்டை',
      'version': 'பதிப்பு',
      'cancel': 'ரத்து செய்',
      'submit': 'சமர்ப்பிக்க',
      'close': 'மூடு',
      'ok': 'சரி',
      'success': 'வெற்றி',
      'error': 'பிழை',
    },

    // ===== HELP SCREEN =====
    'help_en': {
      'title': 'Help & Support',
      'how_can_we_help': 'How can we help?',
      'select_topic': 'Select a topic below',
      'quick_actions': 'Quick Actions',
      'reset_password': 'Reset Password',
      'report_issue': 'Report Issue',
      'live_chat': 'Live Chat',
      'faq': 'Frequently Asked Questions',
      'still_need_help': 'Still need help?',
      'support_247': '24/7 Support',
      'report_submitted': 'Report submitted! Thank you.',
      'enter_title': 'Enter a title',
      'enter_description': 'Enter a description',
    },
    'help_si': {
      'title': 'උදව් සහ සහාය',
      'how_can_we_help': 'අපට ඔබට උදව් කළ හැක්කේ කෙසේද?',
      'select_topic': 'පහත මාතෘකාවක් තෝරන්න',
      'quick_actions': 'ඉක්මන් ක්‍රියා',
      'reset_password': 'මුරපදය යළි සකසන්න',
      'report_issue': 'ගැටලුවක් වාර්තා කරන්න',
      'live_chat': 'සජීවී කතාබහ',
      'faq': 'නිතර අසන ප්‍රශ්න',
      'still_need_help': 'තවත් උදව් අවශ්‍යද?',
      'support_247': 'පැය 24/7 සහාය',
      'report_submitted': 'වාර්තාව ඉදිරිපත් කරන ලදී! ස්තුතියි.',
      'enter_title': 'මාතෘකාවක් ඇතුළත් කරන්න',
      'enter_description': 'විස්තරයක් ඇතුළත් කරන්න',
    },
    'help_ta': {
      'title': 'உதவி மற்றும் ஆதரவு',
      'how_can_we_help': 'நாங்கள் உங்களுக்கு எவ்வாறு உதவ முடியும்?',
      'select_topic': 'கீழே ஒரு தலைப்பைத் தேர்ந்தெடுக்கவும்',
      'quick_actions': 'விரைவு செயல்கள்',
      'reset_password': 'கடவுச்சொல்லை மீட்டமைக்க',
      'report_issue': 'சிக்கலைப் புகாரளிக்க',
      'live_chat': 'நேரலை அரட்டை',
      'faq': 'அடிக்கடி கேட்கப்படும் கேள்விகள்',
      'still_need_help': 'இன்னும் உதவி தேவையா?',
      'support_247': '24/7 ஆதரவு',
      'report_submitted': 'அறிக்கை சமர்ப்பிக்கப்பட்டது! நன்றி.',
      'enter_title': 'தலைப்பை உள்ளிடவும்',
      'enter_description': 'விளக்கத்தை உள்ளிடவும்',
    },

    // ===== CONTACT SCREEN =====
    'contact_en': {
      'title': 'Contact Us',
      'how_can_we_help': 'Get in touch',
      'select_topic': 'We are here to help!',
      'quick_actions': 'Quick Actions',
      'call_us': 'Call Us',
      'email_us': 'Email Us',
      'chat_with_us': 'Chat with Us',
      'office_hours': 'Office Hours',
      'address': '123 Main Street, Colombo, Sri Lanka',
      'send_message': 'Send Message',
      'your_name': 'Your Name',
      'your_email': 'Your Email',
      'your_message': 'Your Message',
      'message_sent': 'Message sent successfully!',
    },
    'contact_si': {
      'title': 'අමතන්න',
      'how_can_we_help': 'සම්බන්ධ වන්න',
      'select_topic': 'අපි ඔබට උදව් කිරීමට මෙහි සිටිමු!',
      'quick_actions': 'ඉක්මන් ක්‍රියා',
      'call_us': 'අපට කතා කරන්න',
      'email_us': 'අපට ඊමේල් කරන්න',
      'chat_with_us': 'අප සමඟ කතාබහ කරන්න',
      'office_hours': 'කාර්යාල වේලාවන්',
      'address': '123 මේන් වීදිය, කොළඹ, ශ්‍රී ලංකාව',
      'send_message': 'පණිවිඩය යවන්න',
      'your_name': 'ඔබගේ නම',
      'your_email': 'ඔබගේ ඊමේල්',
      'your_message': 'ඔබගේ පණිවිඩය',
      'message_sent': 'පණිවිඩය සාර්ථකව යවන ලදී!',
    },
    'contact_ta': {
      'title': 'தொடர்பு கொள்ள',
      'how_can_we_help': 'தொடர்பு கொள்ளுங்கள்',
      'select_topic': 'உங்களுக்கு உதவ நாங்கள் இங்கே!',
      'quick_actions': 'விரைவு செயல்கள்',
      'call_us': 'எங்களை அழைக்க',
      'email_us': 'மின்னஞ்சல் செய்ய',
      'chat_with_us': 'எங்களுடன் அரட்டை',
      'office_hours': 'அலுவலக நேரம்',
      'address': '123 மெயின் வீதி, கொழும்பு, இலங்கை',
      'send_message': 'செய்தி அனுப்ப',
      'your_name': 'உங்கள் பெயர்',
      'your_email': 'உங்கள் மின்னஞ்சல்',
      'your_message': 'உங்கள் செய்தி',
      'message_sent': 'செய்தி வெற்றிகரமாக அனுப்பப்பட்டது!',
    },

    // ===== ABOUT SCREEN =====
    'about_en': {
      'title': 'About Us',
      'how_can_we_help': 'About MySalon',
      'select_topic': 'Your trusted salon booking platform',
      'quick_actions': 'Quick Actions',
      'app_name': 'MySalon',
      'mission': 'Our Mission',
      'mission_text': 'To provide the best salon experience',
      'features': 'Features',
      'privacy': 'Privacy Policy',
      'terms': 'Terms of Service',
      'rate_us': 'Rate Us',
    },
    'about_si': {
      'title': 'අප ගැන',
      'how_can_we_help': 'MySalon ගැන',
      'select_topic': 'ඔබේ විශ්වාසවන්ත සැලෝන් වේදිකාව',
      'quick_actions': 'ඉක්මන් ක්‍රියා',
      'app_name': 'MySalon',
      'mission': 'අපගේ මෙහෙවර',
      'mission_text': 'හොඳම සැලෝන් අත්දැකීම ලබා දීම',
      'features': 'විශේෂාංග',
      'privacy': 'රහස්‍යතා ප්‍රතිපත්තිය',
      'terms': 'සේවා කොන්දේසි',
      'rate_us': 'අපව ඇගයීමට',
    },
    'about_ta': {
      'title': 'எங்களை பற்றி',
      'how_can_we_help': 'MySalon பற்றி',
      'select_topic': 'உங்கள் நம்பிக்கையான சலூன் முன்பதிவு தளம்',
      'quick_actions': 'விரைவு செயல்கள்',
      'app_name': 'MySalon',
      'mission': 'எங்கள் நோக்கம்',
      'mission_text': 'சிறந்த சலூன் அனுபவத்தை வழங்க',
      'features': 'அம்சங்கள்',
      'privacy': 'தனியுரிமைக் கொள்கை',
      'terms': 'சேவை விதிமுறைகள்',
      'rate_us': 'எங்களை மதிப்பிடுங்கள்',
    },
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScreenSize();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final isWeb = size.width > 800;
    final isSmallPhone = size.width < 360;

    if (_isTablet != isTablet ||
        _isWeb != isWeb ||
        _isSmallPhone != isSmallPhone) {
      setState(() {
        _isTablet = isTablet;
        _isWeb = isWeb;
        _isSmallPhone = isSmallPhone;
      });
    }
  }

  // ============== TRANSLATION HELPER ==============
  String t(String key) {
    String screen = widget.screenType;
    String lang = _selectedLanguage;

    String screenKey = '${screen}_$lang';
    if (_strings.containsKey(screenKey) &&
        _strings[screenKey]!.containsKey(key)) {
      return _strings[screenKey]![key]!;
    }

    String screenEnKey = '${screen}_en';
    if (_strings.containsKey(screenEnKey) &&
        _strings[screenEnKey]!.containsKey(key)) {
      return _strings[screenEnKey]![key]!;
    }

    if (_strings.containsKey(lang) && _strings[lang]!.containsKey(key)) {
      return _strings[lang]![key]!;
    }

    return _strings['en']?[key] ?? key;
  }

  // ============== EMAIL ==============
  Future<void> _sendEmail({
    String email = 'support@mysalon.com',
    String subject = '',
    String body = '',
  }) async {
    debugPrint('Sending email...');

    if (kIsWeb) {
      try {
        final url =
            'https://mail.google.com/mail/?view=cm&fs=1&to=$email&su=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        _showSnackBar(t('success'), 'Opening Gmail...', Colors.green);
        return;
      } catch (e) {
        debugPrint('Gmail failed: $e');
      }

      try {
        final url =
            'https://outlook.live.com/mail/0/deeplink/compose?to=$email&subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        _showSnackBar(t('success'), 'Opening Outlook...', Colors.green);
        return;
      } catch (e) {
        debugPrint('Outlook failed: $e');
      }

      _showEmailCopyDialog(email);
    } else {
      try {
        final url =
            'mailto:$email?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        _showSnackBar(t('success'), 'Opening email app...', Colors.green);
      } catch (e) {
        debugPrint('Mobile email failed: $e');
        _showEmailCopyDialog(email);
      }
    }
  }

  // ============== PHONE CALL ==============
  Future<void> _makePhoneCall(String phoneNumber) async {
    debugPrint('Calling...');

    if (kIsWeb) {
      _showWebCallDialog(phoneNumber);
    } else {
      try {
        await launchUrl(
          Uri.parse('tel:$phoneNumber'),
          mode: LaunchMode.externalApplication,
        );
      } catch (e) {
        debugPrint('Call failed: $e');
        _showCallOptionsDialog(phoneNumber);
      }
    }
  }

  // ============== WHATSAPP ==============
  Future<void> _openWhatsApp() async {
    try {
      await launchUrl(
        Uri.parse('https://wa.me/1234567890'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      _showSnackBar(t('error'), 'Please install WhatsApp', Colors.orange);
    }
  }

  // ============== MESSENGER ==============
  Future<void> _openMessenger() async {
    try {
      await launchUrl(
        Uri.parse('https://m.me/mysalonapp'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      _showSnackBar(t('error'), 'Cannot open Messenger', Colors.orange);
    }
  }

  // ============== TELEGRAM ==============
  Future<void> _openTelegram() async {
    try {
      await launchUrl(
        Uri.parse('https://t.me/mysalon_support'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      _showSnackBar(t('error'), 'Cannot open Telegram', Colors.orange);
    }
  }

  // ============== DIALOG SHELL (fixes bottom overflow) ==============
  // Every dialog's content now goes through this helper so it scrolls
  // instead of overflowing on short / landscape screens, and gets a
  // max-height clamp so it never tries to be taller than the viewport.
  Widget _scrollableDialogContent(Widget child) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: SingleChildScrollView(child: child),
    );
  }

  // ============== DIALOGS ==============
  void _showEmailCopyDialog(String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '📧 ${t('email')}',
          style: TextStyle(
            color: context.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: _scrollableDialogContent(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                kIsWeb
                    ? 'Cannot open email from web. Copy and send manually:'
                    : 'Cannot open email app. Copy and send manually:',
                style: TextStyle(color: context.secondaryTextColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.isDarkMode
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey.shade50,
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
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              t('close'),
              style: TextStyle(color: context.secondaryTextColor),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              context.pop();
              _showSnackBar(t('success'), 'Email copied', Colors.green);
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy Email'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showWebCallDialog(String phoneNumber) {
    String message = _selectedLanguage == 'si'
        ? 'වෙබ් බ්‍රවුසරයෙන් කෙලින්ම ඇමතුමක් ගත නොහැක. අංකය පිටපත් කරගෙන අතින් අමතන්න:'
        : _selectedLanguage == 'ta'
        ? 'இணைய உலாவியில் நேரடியாக அழைக்க முடியாது. எண்ணை நகலெடுத்து கைமுறையாக அழைக்கவும்:'
        : 'Cannot make direct calls from web browser. Copy number and call manually:';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.backgroundColor,
        title: Text(
          '📞 ${t('call')}',
          style: TextStyle(
            color: context.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: _scrollableDialogContent(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: TextStyle(color: context.secondaryTextColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.isDarkMode
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
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
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              t('close'),
              style: TextStyle(color: context.secondaryTextColor),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              context.pop();
              _showSnackBar(t('success'), 'Number copied', Colors.green);
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy Number'),
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
        backgroundColor: context.backgroundColor,
        title: Text(
          'Call Options',
          style: TextStyle(
            color: context.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: _scrollableDialogContent(
          // ✅ Explicit opaque color (not MaterialType.transparency) gives the
          // ListTile ink splash a real surface to paint on.
          Material(
            color: context.backgroundColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.call,
                      color: Colors.green,
                      size: 24,
                    ),
                  ),
                  title: Text(
                    'Call Now',
                    style: TextStyle(color: context.textColor),
                  ),
                  subtitle: Text(
                    phoneNumber,
                    style: TextStyle(color: context.secondaryTextColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    context.pop();
                    _makePhoneCall(phoneNumber);
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
                    'Copy Number',
                    style: TextStyle(color: context.textColor),
                  ),
                  subtitle: Text(
                    phoneNumber,
                    style: TextStyle(color: context.secondaryTextColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    context.pop();
                    _showSnackBar(t('success'), 'Number copied', Colors.green);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showChatDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 700;
    final dialogWidth = isWeb ? 420.0 : screenWidth * 0.9;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: context.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contact Support',
                  style: TextStyle(
                    color: context.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Material(
                      color: context.backgroundColor,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildChatOption(
                            Icons.message,
                            Colors.green,
                            'WhatsApp',
                            'Quick response',
                            _openWhatsApp,
                          ),
                          _buildChatOption(
                            Icons.facebook,
                            Colors.blue,
                            'Messenger',
                            'Facebook',
                            _openMessenger,
                          ),
                          _buildChatOption(
                            Icons.telegram,
                            Colors.lightBlue,
                            'Telegram',
                            'Secure chat',
                            _openTelegram,
                          ),
                          _buildChatOption(
                            Icons.email,
                            Colors.orange,
                            t('email'),
                            'support@mysalon.com',
                            () => _sendEmail(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.pop(),
                    child: Text(
                      t('close'),
                      style: TextStyle(color: context.secondaryTextColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatOption(
    IconData icon,
    Color color,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
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
        style: TextStyle(color: context.textColor, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: context.secondaryTextColor, fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        context.pop();
        onTap();
      },
    );
  }

  void _showReportDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          t('report_issue'),
          style: TextStyle(
            color: context.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: _scrollableDialogContent(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: TextStyle(color: context.textColor),
                decoration: InputDecoration(
                  hintText: t('enter_title'),
                  hintStyle: TextStyle(color: context.secondaryTextColor),
                  filled: true,
                  fillColor: context.isDarkMode
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                style: TextStyle(color: context.textColor),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: t('enter_description'),
                  hintStyle: TextStyle(color: context.secondaryTextColor),
                  filled: true,
                  fillColor: context.isDarkMode
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              t('cancel'),
              style: TextStyle(color: context.secondaryTextColor),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.isNotEmpty &&
                  descController.text.isNotEmpty) {
                _saveReport(titleController.text, descController.text);
                context.pop();
                _showSnackBar(
                  t('success'),
                  t('report_submitted'),
                  Colors.green,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            child: Text(t('submit')),
          ),
        ],
      ),
    );
  }

  Future<void> _saveReport(String title, String description) async {
    try {
      final user = supabase.auth.currentUser;
      await supabase.from('reports').insert({
        'user_id': user?.id,
        'email': user?.email ?? 'anonymous@guest',
        'title': title,
        'description': description,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
      debugPrint('Report saved');
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _showSnackBar(String title, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $message'),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ============== LANGUAGE SELECTOR ==============
  // ✅ FIX for "RenderFlex overflowed on the right":
  // The 3-way pill (EN / සිං / த) is only shown on tablet/web where there's
  // room. On phones it collapses to a single compact icon button with a
  // popup menu, so the AppBar row never runs out of horizontal space.
  Widget _buildLanguageSelector() {
    final bool useCompact = !_isWeb && !_isTablet;

    if (useCompact) {
      return PopupMenuButton<String>(
        tooltip: 'Language',
        onSelected: (lang) => setState(() => _selectedLanguage = lang),
        icon: Icon(Icons.language, color: context.textColor),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'en', child: Text('EN — English')),
          PopupMenuItem(value: 'si', child: Text('සිං — සිංහල')),
          PopupMenuItem(value: 'ta', child: Text('த — தமிழ்')),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: context.isDarkMode
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLangOption('EN', 'en'),
          _buildDivider(),
          _buildLangOption('සිං', 'si'),
          _buildDivider(),
          _buildLangOption('த', 'ta'),
        ],
      ),
    );
  }

  Widget _buildLangOption(String text, String langCode) {
    bool isSelected = _selectedLanguage == langCode;

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
            fontSize: _isWeb ? 13 : 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : context.isDarkMode
                ? Colors.white70
                : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 20,
      color: context.isDarkMode
          ? Colors.white.withValues(alpha: 0.2)
          : Colors.grey.shade300,
    );
  }

  // ============================================================
  // ✅ BUILD METHOD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final backgroundColor = context.backgroundColor;
    final textColor = context.textColor;

    Color screenColor = Colors.blue;
    IconData screenIcon = Icons.help_outline;
    String screenTitle = t('title');

    if (widget.screenType == 'contact') {
      screenColor = Colors.purple;
      screenIcon = Icons.headset_mic;
    } else if (widget.screenType == 'about') {
      screenColor = Colors.teal;
      screenIcon = Icons.info_outline;
    }

    _checkScreenSize();

    // ✅ Responsive content width: cap the reading width on web/tablet so
    // things don't stretch awkwardly, keep full width on phones.
    final double maxContentWidth = _isWeb ? 720 : double.infinity;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: Text(
          screenTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: _isSmallPhone ? 16 : 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _buildLanguageSelector(),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildHeader(screenColor, screenIcon),
                const SizedBox(height: 24),
                _buildQuickActions(screenColor),
                const SizedBox(height: 24),
                if (widget.screenType == 'help') ...[
                  _buildFaqSection(),
                  const SizedBox(height: 24),
                  _buildContactCard(),
                ] else if (widget.screenType == 'contact') ...[
                  _buildOfficeHours(),
                  const SizedBox(height: 24),
                  _buildAddressCard(),
                  const SizedBox(height: 24),
                  _buildSocialMedia(),
                  const SizedBox(height: 24),
                  _buildContactForm(),
                ] else if (widget.screenType == 'about') ...[
                  const SizedBox(height: 24),
                  _buildMissionCard(),
                  const SizedBox(height: 24),
                  _buildFeaturesCard(),
                ],
                const SizedBox(height: 24),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============== HEADER ==============
  Widget _buildHeader(Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.8)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('how_can_we_help'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t('select_topic'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============== QUICK ACTIONS ==============
  // ✅ FIX for right/bottom overflow: on narrow phones, 3 cards squeezed
  // into one Row don't have enough width for icon + 2-line label, which
  // is exactly what produced the RenderFlex overflows. We now use a
  // LayoutBuilder + Wrap so cards flow onto a second line instead of
  // being crushed or clipped.
  Widget _buildQuickActions(Color color) {
    List<Map<String, dynamic>> actionData = [];

    if (widget.screenType == 'help') {
      actionData = [
        {
          'icon': Icons.lock_reset,
          'label': t('reset_password'),
          'color': Colors.orange,
          'onTap': () => context.push('/reset-password'),
        },
        {
          'icon': Icons.report_problem,
          'label': t('report_issue'),
          'color': Colors.redAccent,
          'onTap': _showReportDialog,
        },
        {
          'icon': Icons.chat,
          'label': t('live_chat'),
          'color': Colors.green,
          'onTap': _showChatDialog,
        },
      ];
    } else if (widget.screenType == 'contact') {
      actionData = [
        {
          'icon': Icons.phone,
          'label': t('call_us'),
          'color': Colors.green,
          'onTap': () => _makePhoneCall('+94112345678'),
        },
        {
          'icon': Icons.email,
          'label': t('email_us'),
          'color': Colors.blue,
          'onTap': () => _sendEmail(),
        },
        {
          'icon': Icons.chat,
          'label': t('chat_with_us'),
          'color': Colors.orange,
          'onTap': _showChatDialog,
        },
      ];
    } else if (widget.screenType == 'about') {
      actionData = [
        {
          'icon': Icons.privacy_tip,
          'label': t('privacy'),
          'color': Colors.blue,
          'onTap': () => launchUrl(
            Uri.parse('https://mysalon.com/privacy'),
            mode: LaunchMode.externalApplication,
          ),
        },
        {
          'icon': Icons.description,
          'label': t('terms'),
          'color': Colors.orange,
          'onTap': () => launchUrl(
            Uri.parse('https://mysalon.com/terms'),
            mode: LaunchMode.externalApplication,
          ),
        },
        {
          'icon': Icons.star,
          'label': t('rate_us'),
          'color': Colors.amber,
          'onTap': () => launchUrl(
            Uri.parse(
              'https://play.google.com/store/apps/details?id=com.mysalon.app',
            ),
            mode: LaunchMode.externalApplication,
          ),
        },
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('quick_actions'),
          style: TextStyle(
            color: context.textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            // 3 columns on tablet/web/normal phones, 2 columns on small phones.
            final int columns = _isWeb || _isTablet
                ? 3
                : (_isSmallPhone ? 2 : 3);
            const double spacing = 12;
            final double cardWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: actionData.map((data) {
                return SizedBox(
                  width: cardWidth,
                  child: _buildActionCard(
                    data['icon'] as IconData,
                    data['label'] as String,
                    data['color'] as Color,
                    data['onTap'] as VoidCallback,
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionCard(
    IconData icon,
    String title,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: context.isDarkMode
              ? color.withValues(alpha: 0.15)
              : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ============== FAQ SECTION ==============
  Widget _buildFaqSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('faq'),
          style: TextStyle(
            color: context.textColor,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildFaqItem(
          '🔐 ${t('reset_password')}',
          'Click "Reset Password" and enter your email',
        ),
        _buildFaqItem('📝 ${t('report_issue')}', t('report_submitted')),
        _buildFaqItem(
          '💬 ${t('live_chat')}',
          'Click "Live Chat" to connect with our team',
        ),
      ],
    );
  }

  Widget _buildFaqItem(String question, String answer) {
    // ✅ FIX: ExpansionTile renders its own internal ListTile. Giving it to
    // a plain Container with a color decoration is what produced the
    // "ListTile background color or ink splashes may be invisible" warning
    // (Flutter couldn't resolve an opaque Material surface to splash on).
    // Wrapping in an explicit, opaque Material — and using ClipRRect so the
    // splash respects the rounded corners — fixes it properly.
    final Color tileColor = context.isDarkMode
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey.shade50;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: Material(
        color: tileColor,
        child: ExpansionTile(
          // ✅ Prevents right-edge overflow from long localized FAQ questions.
          title: Text(
            question,
            style: TextStyle(color: context.textColor, fontSize: 15),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          collapsedIconColor: Colors.blueAccent,
          iconColor: Colors.blueAccent,
          backgroundColor: tileColor,
          collapsedBackgroundColor: tileColor,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                answer,
                style: TextStyle(color: context.secondaryTextColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============== CONTACT CARD ==============
  // ✅ FIX: 3 buttons in a fixed Row overflow on very narrow phones once
  // labels grow beyond ~1-2 chars. Wrapping in a LayoutBuilder + Wrap lets
  // them drop to 2-per-row instead of overflowing.
  Widget _buildContactCard() {
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
            t('still_need_help'),
            style: TextStyle(
              color: context.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            t('support_247'),
            style: TextStyle(color: context.secondaryTextColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              if (_isSmallPhone) {
                // Stack vertically on very narrow phones.
                return Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: _buildOutlinedButton(
                        Icons.email,
                        t('email'),
                        () => _sendEmail(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: _buildOutlinedButton(
                        Icons.phone,
                        t('call'),
                        () => _makePhoneCall('+94112345678'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: _buildFilledButton(
                        Icons.chat,
                        t('chat'),
                        _showChatDialog,
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: _buildOutlinedButton(
                      Icons.email,
                      t('email'),
                      () => _sendEmail(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildOutlinedButton(
                      Icons.phone,
                      t('call'),
                      () => _makePhoneCall('+94112345678'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFilledButton(
                      Icons.chat,
                      t('chat'),
                      _showChatDialog,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOutlinedButton(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: context.isDarkMode ? Colors.white : Colors.black87,
        side: BorderSide(
          color: context.isDarkMode
              ? Colors.white.withValues(alpha: 0.5)
              : Colors.grey.shade400,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }

  Widget _buildFilledButton(IconData icon, String label, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ============== OFFICE HOURS ==============
  Widget _buildOfficeHours() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Monday - Friday',
                style: TextStyle(color: context.secondaryTextColor),
              ),
              Text(
                '9:00 AM - 6:00 PM',
                style: TextStyle(color: context.textColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Saturday - Sunday',
                style: TextStyle(color: context.secondaryTextColor),
              ),
              const Text('Closed', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ],
      ),
    );
  }

  // ============== ADDRESS CARD ==============
  Widget _buildAddressCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on,
              color: Colors.purple,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Visit Us',
                  style: TextStyle(
                    color: context.textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t('address'),
                  style: TextStyle(color: context.secondaryTextColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============== SOCIAL MEDIA ==============
  Widget _buildSocialMedia() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            'Follow Us',
            style: TextStyle(
              color: context.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // ✅ Wrap instead of a fixed Row so icons reflow on very narrow screens
          // instead of overflowing.
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 20,
            runSpacing: 12,
            children: [
              _buildSocialIcon(Icons.facebook, Colors.blue, _openMessenger),
              _buildSocialIcon(Icons.photo_camera, Colors.pink, () {}),
              _buildSocialIcon(Icons.message, Colors.green, _openWhatsApp),
              _buildSocialIcon(Icons.telegram, Colors.lightBlue, _openTelegram),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSocialIcon(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.isDarkMode
              ? color.withValues(alpha: 0.15)
              : color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  // ============== CONTACT FORM ==============
  Widget _buildContactForm() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final messageController = TextEditingController();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('send_message'),
            style: TextStyle(
              color: context.textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: nameController,
            style: TextStyle(color: context.textColor),
            decoration: InputDecoration(
              hintText: t('your_name'),
              hintStyle: TextStyle(color: context.secondaryTextColor),
              filled: true,
              fillColor: context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: emailController,
            style: TextStyle(color: context.textColor),
            decoration: InputDecoration(
              hintText: t('your_email'),
              hintStyle: TextStyle(color: context.secondaryTextColor),
              filled: true,
              fillColor: context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: messageController,
            style: TextStyle(color: context.textColor),
            maxLines: 3,
            decoration: InputDecoration(
              hintText: t('your_message'),
              hintStyle: TextStyle(color: context.secondaryTextColor),
              filled: true,
              fillColor: context.isDarkMode
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                _sendEmail(
                  email: 'support@mysalon.com',
                  subject: 'Contact Form: ${nameController.text}',
                  body:
                      'Name: ${nameController.text}\nEmail: ${emailController.text}\nMessage: ${messageController.text}',
                );
                _showSnackBar(t('success'), t('message_sent'), Colors.green);
                nameController.clear();
                emailController.clear();
                messageController.clear();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                t('send_message'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============== MISSION ==============
  Widget _buildMissionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? Colors.blue.withValues(alpha: 0.15)
            : Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.rocket, color: Colors.blueAccent, size: 40),
          const SizedBox(height: 12),
          Text(
            t('mission'),
            style: TextStyle(
              color: context.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('mission_text'),
            style: TextStyle(color: context.secondaryTextColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ============== FEATURES ==============
  Widget _buildFeaturesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('features'),
            style: TextStyle(
              color: context.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildFeatureChip(Icons.calendar_today, 'Easy booking'),
              _buildFeatureChip(Icons.security, 'Secure payments'),
              _buildFeatureChip(Icons.person, 'Professional staff'),
              _buildFeatureChip(Icons.support_agent, '24/7 support'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.isDarkMode
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.green.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.green, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.green, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ============== FOOTER ==============
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppVersion.name,
                style: TextStyle(
                  color: context.textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${t('version')}  ${AppVersion.version}',
                style: TextStyle(
                  color: context.secondaryTextColor,
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
