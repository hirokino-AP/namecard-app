import 'package:flutter/material.dart';

void main() {
  runApp(const NamecardApp());
}

class NamecardApp extends StatelessWidget {
  const NamecardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '名刺管理',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF185FA5),
          primary: const Color(0xFF185FA5),
        ),
        useMaterial3: true,
      ),
      home: const ContactListPage(),
    );
  }
}

class ContactListPage extends StatelessWidget {
  const ContactListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F6FD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF185FA5),
        title: const Text(
          '名刺一覧',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: const Center(
        child: Text('名刺管理アプリ起動成功！'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF185FA5),
        onPressed: () {},
        child: const Icon(Icons.camera_alt, color: Colors.white),
      ),
    );
  }
}
