import 'package:flutter/material.dart';

class LoadingProgress {
  static String currentFileName = '';
  static int processedFiles = 0;
  static int totalFiles = 0;
}

class LoadingProgressModel extends StatelessWidget {
  const LoadingProgressModel({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(Duration(milliseconds: 100)),
      builder: (context, snapshot) {
        return SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: LoadingProgress.totalFiles > 0
                    ? LoadingProgress.processedFiles / LoadingProgress.totalFiles
                    : 0,
              ),
              SizedBox(height: 16),
              Text(
                'Processing: ${LoadingProgress.currentFileName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 8),
              Text(
                '${LoadingProgress.processedFiles}/${LoadingProgress.totalFiles} files',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
