# DeepMusic - Changelog

## [Unreleased] - 2026-03-25

### Added
- **乐谱上传功能 (Mobile)**
  - 新增 `ScoreUploadPage` 上传页面
    - 文件选择器（支持 .xml / .mxl / .musicxml 格式）
    - 表单：标题、作曲家（必填）、编曲者、难度、分类、来源、许可证
    - 上传按钮带 loading 状态，成功后自动返回
  - `ScoreRepository` 新增 `uploadScore()` 方法
    - 使用 Dio FormData + MultipartFile 上传
    - 对接后端 `POST /api/scores` 接口
  - 路由注册 `/scores/upload`
  - 乐谱库页面 FAB 按钮接入上传流程

### Dependencies
- 新增 `file_picker: ^6.1.1`

### Files Changed
| 文件 | 变更 |
|------|------|
| `mobile/pubspec.yaml` | 添加 file_picker 依赖 |
| `mobile/lib/data/repositories/score_repository.dart` | 新增 uploadScore() |
| `mobile/lib/features/score/pages/score_upload_page.dart` | 新建上传页面 |
| `mobile/lib/core/router/app_router.dart` | 注册上传路由 |
| `mobile/lib/features/score/pages/score_library_page.dart` | FAB 接入上传 |
