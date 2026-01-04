import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/models/user_model.dart';
import 'package:flutter_application_1/screens/authantication/authenticate_screen.dart';
import 'package:flutter_application_1/screens/home/customer_home.dart';
import 'package:provider/provider.dart';

class Wrapper extends StatelessWidget {
  const Wrapper({super.key});

  @override
  Widget build(BuildContext context) {
    //the user data that the provider provide this can be a user data or can be null
    final user = Provider.of<UserModel?>(context);


    if (user == null || user.uid == '') {
      return Authenticate();
    } else {
      return MaterialApp(home: CustomerHome());
    }
  }
}
