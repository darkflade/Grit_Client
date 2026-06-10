import 'package:flutter/material.dart';
import '../controllers/login_controller.dart';
import '../../core/storage/storage_service.dart';
import '../../data/api/rest.dart';
import '../theme/app_spacing.dart';
import '../theme/app_radii.dart';
import '../widgets/common/app_button.dart';
import '../widgets/common/app_text_field.dart';
import '../widgets/common/app_card.dart';

class LoginScreen extends StatefulWidget {
  final ApiClient apiClient; // Added apiClient field

  const LoginScreen({
    super.key,
    required this.apiClient,
  }); // Updated constructor

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final LoginController _controller;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController(); // For registration

  bool _isLogin = true; // To toggle between login and register
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Use the ApiClient passed via the widget
    final storageService = StorageService();
    _controller = LoginController(
      widget.apiClient,
      storageService,
    ); // Use widget.apiClient
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      bool success;
      if (_isLogin) {
        success = await _controller.login(
          _emailController.text,
          _passwordController.text,
        );
      } else {
        success = await _controller.register(
          _nicknameController.text,
          _emailController.text,
          _passwordController.text,
        );
      }

      setState(() {
        _isLoading = false;
      });

      if (success) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        setState(() {
          _errorMessage =
              _controller.errorMessage ?? "An unknown error occurred.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xxl,
            ),
            child: ConstrainedBox(
              // Mobile: nearly full width (minus padding).
              // Tablet / web: capped so the form stays compact and centered.
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: AppSpacing.xxxl),
                  _buildModeSwitch(context),
                  const SizedBox(height: AppSpacing.lg),
                  _buildFormCard(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: AppRadii.brXl,
          ),
          child: Icon(
            Icons.forum_rounded,
            size: 36,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Diogen',
          textAlign: TextAlign.center,
          style: theme.textTheme.displayMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Secure messaging client',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildModeSwitch(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment<bool>(
          value: true,
          label: Text('Login'),
          icon: Icon(Icons.login_rounded),
        ),
        ButtonSegment<bool>(
          value: false,
          label: Text('Register'),
          icon: Icon(Icons.person_add_alt_1_rounded),
        ),
      ],
      selected: {_isLogin},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        setState(() {
          _isLogin = selection.first;
          _errorMessage = null; // Clear error when switching modes
          _formKey.currentState?.reset(); // Reset form fields
        });
      },
    );
  }

  Widget _buildFormCard(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!_isLogin) ...[
              AppTextField(
                controller: _nicknameController,
                label: 'Nickname',
                prefixIcon: Icons.person_outline_rounded,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your nickname';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AppTextField(
              controller: _emailController,
              label: 'Email',
              prefixIcon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                if (!value.contains('@')) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              controller: _passwordController,
              label: 'Password',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (value.length < 6 && !_isLogin) {
                  // Basic password length for registration
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              _buildErrorBanner(context, _errorMessage!),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: _isLogin ? 'Login' : 'Register',
              fullWidth: true,
              loading: _isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      backgroundColor: scheme.errorContainer,
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppRadii.md,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
