class CustomerAuth {
  final List<String> roles;
  final String firstName;
  final String lastName; 
  final String email;
  final String password;

  CustomerAuth({
    required this.roles,
    required this.firstName,
    required this.lastName,  
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toMap() {
    return {
      'roles': roles,
      'firstName': firstName,
      'lastName': lastName,     
      'email': email,
      'password': password,
    };
  }
}

class CompanyAuth {
  final List<String> roles;
  final String companyName;
  final String companyAddress;
  final String mobile;
  final String email;
  final String password;

  CompanyAuth({
    required this.roles,
    required this.companyName,
    this.companyAddress='',
    this.mobile='',
    required this.email,
    required this.password,
  });

  Map<String, dynamic> toMap() {
    return {
      'roles': roles,
      'companyName': companyName,    
      'email': email,
      'password': password,
    };
  }
}
