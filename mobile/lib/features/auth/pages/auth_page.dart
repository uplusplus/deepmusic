import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../data/repositories/auth_repository.dart';

/// 登录/注册页面
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _authRepo = AuthRepository();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        await _authRepo.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await _authRepo.register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          nickname: _nicknameController.text.trim().isNotEmpty
              ? _nicknameController.text.trim()
              : null,
        );
      }

      if (mounted) {
        Navigator.of(context).pushReplacementNamed(AppRouter.home);
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleMode() {
    setState(() => _isLogin = !_isLogin);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),

                // Logo + 标题
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.piano,
                          size: 40,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'DeepMusic',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isLogin ? '欢迎回来' : '创建账号',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                // 注册时显示昵称
                if (!_isLogin) ...[
                  TextFormField(
                    controller: _nicknameController,
                    decoration: InputDecoration(
                      labelText: '昵称',
                      hintText: '给自己取个名字',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                ],

                // 邮箱
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: '邮箱',
                    hintText: 'your@email.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入邮箱';
                    }
                    if (!value.contains('@')) {
                      return '请输入有效邮箱';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // 密码
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: '密码',
                    hintText: '至少 6 位',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入密码';
                    }
                    if (value.length < 6) {
                      return '密码至少 6 位';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // 提交按钮
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isLogin ? '登录' : '注册'),
                  ),
                ),

                const SizedBox(height: 16),

                // 切换登录/注册
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isLogin ? '还没有账号？' : '已有账号？',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    TextButton(
                      onPressed: _isLoading ? null : _toggleMode,
                      child: Text(
                        _isLogin ? '立即注册' : '去登录',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // 跳过登录
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed(AppRouter.home);
                    },
                    child: const Text(
                      '跳过登录，先看看',
                      style: TextStyle(color: AppColors.textHint),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
