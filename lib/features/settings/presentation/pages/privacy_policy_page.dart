import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('開發理念')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              context,
              title: '資料自主權',
              content:
                  '我們不會對用戶的資料做任何防止匯出的措施，我們相信，資料是用戶最寶貴的財產，並且為用戶提供了多種資料匯出和同步的方式。',
            ),
            const SizedBox(height: 24),
            _buildSection(
              context,
              title: '隱私與安全',
              content: '我們不會審查用戶的日記。當雲同步功能上線後，用戶同步到雲的資料會是加密的，確保您的隱私得到最大程度的保護。',
            ),
            const SizedBox(height: 24),
            _buildSection(
              context,
              title: '本機優先',
              content:
                  '目前版本（MVP）的所有資料均儲存在您的本機裝置上。除非您主動分享或匯出，否則這些資料不會透過網路傳輸到任何第三方伺服器。',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String content,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
      ],
    );
  }
}
