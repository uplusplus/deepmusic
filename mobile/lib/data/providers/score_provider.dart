import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/score_repository.dart';
import '../../data/services/api_client.dart';

/// API 客户端 Provider
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

/// 乐谱仓库 Provider
final scoreRepositoryProvider = Provider<ScoreRepository>((ref) {
  return ScoreRepository(apiClient: ref.watch(apiClientProvider));
});

/// 乐谱列表 Provider
final scoreListProvider = FutureProvider.family<ScoreListResult, ScoreListParams>((ref, params) async {
  final repository = ref.watch(scoreRepositoryProvider);
  return repository.getScores(
    page: params.page,
    limit: params.limit,
    difficulty: params.difficulty,
    category: params.category,
    search: params.search,
  );
});

/// 推荐乐谱 Provider
final recommendedScoresProvider = FutureProvider<List<ScoreModel>>((ref) async {
  final repository = ref.watch(scoreRepositoryProvider);
  return repository.getRecommendedScores();
});

/// 乐谱详情 Provider
final scoreDetailProvider = FutureProvider.family<ScoreModel, String>((ref, id) async {
  final repository = ref.watch(scoreRepositoryProvider);
  return repository.getScoreById(id);
});

/// 搜索乐谱 Provider
final scoreSearchProvider = FutureProvider.family<List<ScoreModel>, String>((ref, query) async {
  final repository = ref.watch(scoreRepositoryProvider);
  return repository.searchScores(query);
});

/// 乐谱列表查询参数
class ScoreListParams {
  final int page;
  final int limit;
  final String? difficulty;
  final String? category;
  final String? search;

  const ScoreListParams({
    this.page = 1,
    this.limit = 20,
    this.difficulty,
    this.category,
    this.search,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScoreListParams &&
          runtimeType == other.runtimeType &&
          page == other.page &&
          limit == other.limit &&
          difficulty == other.difficulty &&
          category == other.category &&
          search == other.search;

  @override
  int get hashCode =>
      page.hashCode ^
      limit.hashCode ^
      difficulty.hashCode ^
      category.hashCode ^
      search.hashCode;
}
