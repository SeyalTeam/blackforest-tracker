import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login.dart';

class CommonScaffold extends StatelessWidget {
  final Widget body;
  final String title;

  const CommonScaffold({
    super.key,
    required this.body,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.black,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                   CircleAvatar(
                     backgroundColor: Colors.white,
                     child: Icon(Icons.person, color: Colors.black),
                   ),
                   SizedBox(height: 10),
                   Text(
                    'Admin Panel',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context); // Close drawer
                // Already on home, maybe simple pop or do nothing
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory),
              title: const Text('Stock'),
              onTap: () {
                 Navigator.pop(context);
                 // Navigate to Stock
              },
            ),
             ListTile(
              leading: const Icon(Icons.assignment_return),
              title: const Text('Return'),
              onTap: () {
                 Navigator.pop(context);
                 // Navigate to Return
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                const storage = FlutterSecureStorage();
                await storage.deleteAll();
                
                 if (context.mounted) {
                   Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                    (route) => false,
                  );
                 }
              },
            ),
          ],
        ),
      ),
      body: body,
    );
  }
}
