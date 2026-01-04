// bool isValidEmail(String email) {
//   final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
//   return emailRegex.hasMatch(email);
// }

// bool isValidMobile(String mobile) {
//   final phoneRegex = RegExp(r'^\+?[0-9]{10,10}$');
//   return phoneRegex.hasMatch(mobile);
// }

bool isEmail(String input) {
  final emailReg = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
  return emailReg.hasMatch(input);
}

bool isMobile(String input) {
  final mobileReg = RegExp(r'^[0-9]{10}$');
  return mobileReg.hasMatch(input);
}

