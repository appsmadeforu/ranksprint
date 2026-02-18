import 'package:flutter/material.dart';

class PyqScreen extends StatelessWidget {
  const PyqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Previous Year Questions")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(title: Text("UPSC CSE")),
          ListTile(title: Text("SSC CGL")),
          ListTile(title: Text("Bank PO")),
        ],
      ),
    );
  }
}
