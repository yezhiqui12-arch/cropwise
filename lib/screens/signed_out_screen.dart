import 'package:flutter/material.dart';

import 'account_access_screen.dart';

class SignedOutScreen extends StatelessWidget {
  const SignedOutScreen({super.key});

  @override
  Widget build(BuildContext context) => const AccountAccessScreen(
    allowContinueAsGuest: true,
    replaceWithHomeOnSuccess: true,
    brandedLanding: true,
  );
}
