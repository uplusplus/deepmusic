import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/repositories/score_repository.dart';

/// 乐谱上传页面
class ScoreUploadPage extends StatefulWidget {
  const ScoreUploadPage({super.key});

  @override
  State<ScoreUploadPage> createState() => _ScoreUploadPageState();
}

class _ScoreUploadPageState extends State<ScoreUploadPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _composerController = TextEditingController();
  final _arrangerController = TextEditingController();
  final _categoryController = TextEditingController();
  final _sourceController = TextEditingController();
  final _licenseController = TextEditingController();

  String _difficulty = 'BEGINNER';
  String? _selectedFileName;
  String? _selectedFilePath;
  bool _isUploading = false;

  final ScoreRepository _scoreRepository = ScoreRepository();

  static const _difficultyOptions = [
    {'value': 'BEGINNER', 'label': '初级'},
    {'value': 'INTERMEDIATE', 'label': '中级'},
    {'value': 'ADVANCED', 'label': '高级'},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _composerController.dispose();
    _arrangerController.dispose();
    _categoryController.dispose();
    _sourceController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  /// 选择 MusicXML 文件
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml', 'mxl', 'musicxml'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _selectedFileName = file.name;
          _selectedFilePath = file.path;
        });
      }
    } catch (e) {
      _showSnackBar('选择文件失败：$e');
    }
  }

  /// 执行上传
  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedFilePath == null) {
      _showSnackBar('请先选择乐谱文件');
      return;
    }

    setState(() => _isUploading = true);

    try {
      final score = await _scoreRepository.uploadScore(
        filePath: _selectedFilePath!,
        title: _titleController.text.trim(),
        composer: _composerController.text.trim(),
        arranger: _arrangerController.text.trim().isEmpty
            ? null
            : _arrangerController.text.trim(),
        difficulty: _difficulty,
        category: _categoryController.text.trim().isEmpty
            ? null
            : _categoryController.text.trim(),
        source: _sourceController.text.trim().isEmpty
            ? null
            : _sourceController.text.trim(),
        license: _licenseController.text.trim().isEmpty
            ? null
            : _licenseController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('乐谱「${score.title}」上传成功'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).pop(score);
    } on ScoreException catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      _showSnackBar('上传失败：${e.message}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      _showSnackBar('上传失败：$e');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('上传乐谱'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 文件选择区
              _buildFilePicker(),
              const SizedBox(height: 24),

              // 标题
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '乐谱标题 *',
                  hintText: '例如：致爱丽丝',
                  prefixIcon: Icon(Icons.title),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入乐谱标题' : null,
              ),
              const SizedBox(height: 16),

              // 作曲家
              TextFormField(
                controller: _composerController,
                decoration: const InputDecoration(
                  labelText: '作曲家 *',
                  hintText: '例如：贝多芬',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入作曲家' : null,
              ),
              const SizedBox(height: 16),

              // 编曲者
              TextFormField(
                controller: _arrangerController,
                decoration: const InputDecoration(
                  labelText: '编曲者（选填）',
                  prefixIcon: Icon(Icons.edit),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 难度
              DropdownButtonFormField<String>(
                value: _difficulty,
                decoration: const InputDecoration(
                  labelText: '难度',
                  prefixIcon: Icon(Icons.signal_cellular_alt),
                  border: OutlineInputBorder(),
                ),
                items: _difficultyOptions
                    .map((d) => DropdownMenuItem(
                          value: d['value'],
                          child: Text(d['label']!),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _difficulty = v!),
              ),
              const SizedBox(height: 16),

              // 分类
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: '分类（选填）',
                  hintText: '例如：古典、流行',
                  prefixIcon: Icon(Icons.category),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 来源
              TextFormField(
                controller: _sourceController,
                decoration: const InputDecoration(
                  labelText: '来源（选填）',
                  prefixIcon: Icon(Icons.source),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 许可证
              TextFormField(
                controller: _licenseController,
                decoration: const InputDecoration(
                  labelText: '许可证（选填）',
                  hintText: '例如：CC0, Public Domain',
                  prefixIcon: Icon(Icons.gavel),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 32),

              // 上传按钮
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isUploading ? null : _upload,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_upload),
                  label: Text(_isUploading ? '上传中...' : '上传乐谱'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilePicker() {
    final hasFile = _selectedFilePath != null;

    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: hasFile
              ? AppColors.primary.withOpacity(0.05)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasFile ? AppColors.primary : Colors.grey.shade300,
            width: hasFile ? 2 : 1,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Icon(
              hasFile ? Icons.description : Icons.upload_file,
              size: 48,
              color: hasFile ? AppColors.primary : Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              hasFile ? _selectedFileName! : '点击选择 MusicXML 文件',
              style: TextStyle(
                fontSize: 16,
                fontWeight: hasFile ? FontWeight.w600 : FontWeight.normal,
                color: hasFile ? AppColors.primary : Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '支持 .xml / .mxl / .musicxml 格式',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            if (hasFile) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => setState(() {
                  _selectedFileName = null;
                  _selectedFilePath = null;
                }),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('移除文件'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
